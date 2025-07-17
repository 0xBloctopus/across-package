import { ethers } from 'ethers';
import { createClient, RedisClientType} from 'redis';
import { MerkleTree } from 'merkletreejs';
import { BigNumberish } from "ethers";
import 'dotenv/config'; 

interface DataWorkerConfig {
  hubPool: { rpc: string; privateKey: string; address: string };
  chainA: { rpc: string; spokePoolAddress: string; chainId: number };
  chainB: { rpc: string; spokePoolAddress: string; chainId: number };
  redisUrl: string;
  pollingInterval?: number;
  blockRange?: number;
  minRefundVolume?: string; // Minimum volume before submitting refund bundle
}

interface RelayData {
  chain: string;
  inputToken: string;
  outputToken: string;
  inputAmount: string;
  outputAmount: string;
  repaymentChainId: string;
  originChainId: string;
  depositId: string;
  relayer: string;
  timestamp: number;
  blockNumber: number;
  transactionHash: string;
}

interface RelayerRefund {
  relayer: string;
  token: string;
  amount: string;
  chainId: number;
  refundCounter: number;
}

interface RelayerRefundLeaf {
  amountToReturn: BigNumberish;
  chainId: BigNumberish;
  refundAmounts: BigNumberish[];
  leafId: number;
  l2TokenAddress: string;
  refundAddresses: string[];
}

interface PoolRebalanceLeaf {
  chainId: BigNumberish;
  bundleLpFees: BigNumberish[];
  netSendAmounts: BigNumberish[];
  runningBalances: BigNumberish[];
  groupIndex: BigNumberish;
  leafId: number;
  l1Tokens: string[];
}
class AcrossDataWorker {
  private hubPoolProvider: ethers.JsonRpcProvider;
  private hubPoolWallet: ethers.Wallet;
  private hubPool: ethers.Contract;
  private providerA: ethers.JsonRpcProvider;
  private providerB: ethers.JsonRpcProvider;
  private walletA: ethers.Wallet;
  private walletB: ethers.Wallet;
  private spokePoolA: ethers.Contract;
  private spokePoolB: ethers.Contract;
  private redis: RedisClientType;
  private relayData: RelayData[] = [];
  private relayerRefunds: Map<string, RelayerRefund[]> = new Map();
  private relayerRefundLeaves: RelayerRefundLeaf[] = [];
  private poolRebalanceLeaves: PoolRebalanceLeaf[] = [];
  private pollingInterval: number;
  private lastProcessedBlockA: number = 0;
  private lastProcessedBlockB: number = 0;
  private isRunning: boolean = false;
  private blockRange: number;
  private minRefundVolume: bigint;
  private refundCounter: number = 0;

  constructor(config: DataWorkerConfig) {
    this.hubPoolProvider = new ethers.JsonRpcProvider(config.hubPool.rpc);
    this.hubPoolWallet = new ethers.Wallet(config.hubPool.privateKey, this.hubPoolProvider);
    
    const hubPoolAbi = [
      "function proposeRootBundle(uint256[] calldata bundleEvaluationBlockNumbers, uint8 poolRebalanceLeafCount, bytes32 poolRebalanceRoot, bytes32 relayerRefundRoot, bytes32 slowRelayRoot)",
      "function getCurrentTime() view returns (uint256)",
      "function liveness() view returns (uint32)",
      "function rootBundleProposal() view returns (bytes32 poolRebalanceRoot, bytes32 relayerRefundRoot, bytes32 slowRelayRoot, uint256 claimedBitMap, address proposer, uint8 unclaimedPoolRebalanceLeafCount, uint32 challengePeriodEndTimestamp)",
      "function executeRootBundle(uint256 chainId, uint256 groupIndex, uint256[] memory bundleLpFees, int256[] memory netSendAmounts, int256[] memory runningBalances, uint8 leafId, address[] memory l1Tokens, bytes32[] memory proof)" ] ;
    this.hubPool = new ethers.Contract(config.hubPool.address, hubPoolAbi, this.hubPoolWallet);
    
    this.providerA = new ethers.JsonRpcProvider(config.chainA.rpc);
    this.providerB = new ethers.JsonRpcProvider(config.chainB.rpc);

    // Create wallets for each chain using the same private key as hubPool
    this.walletA = new ethers.Wallet(config.hubPool.privateKey, this.providerA);
    this.walletB = new ethers.Wallet(config.hubPool.privateKey, this.providerB);

    const spokePoolAbi = [
      "event FilledRelay(bytes32 indexed inputToken, bytes32 indexed outputToken, uint256 inputAmount, uint256 outputAmount, uint256 repaymentChainId, uint256 indexed originChainId, uint256 indexed depositId, uint32 fillDeadline, uint32 exclusivityDeadline, bytes32 exclusiveRelayer, bytes32 indexed relayer, bytes32 depositor, bytes32 recipient, bytes32 messageHash, tuple(bytes32 updatedRecipient, bytes32 updatedMessageHash,uint256 updatedOutputAmount, uint8 fillType) relayExecutionInfo)",
      "function executeRelayerRefundLeaf(uint32 rootBundleId, tuple(uint256 amountToReturn, uint256 chainId, uint256[] refundAmounts, uint32 leafId, address l2TokenAddress, address[] refundAddresses), bytes32[] memory proof)",
    ];
    
    // Connect spokePool contracts to wallets (signers)
    this.spokePoolA = new ethers.Contract(config.chainA.spokePoolAddress, spokePoolAbi, this.walletA);
    this.spokePoolB = new ethers.Contract(config.chainB.spokePoolAddress, spokePoolAbi, this.walletB);
    this.redis = createClient({ url: config.redisUrl });
    this.pollingInterval = config.pollingInterval || 15000;
    this.blockRange = config.blockRange || 100;
    this.minRefundVolume = ethers.parseEther("0"); // Default 1000 ETH equivalent
  }

  async start() {
    await this.redis.connect();
    // Load relayer refund leaves from Redis if they exist
    const leavesJson = await this.redis.get('lastRelayerRefundLeaves');
    if (leavesJson) {
      this.relayerRefundLeaves = JSON.parse(leavesJson);
      console.log('Loaded relayer refund leaves from Redis:', this.relayerRefundLeaves.length);
    }
    const poolLeavesJson = await this.redis.get('lastPoolRebalanceLeaves');
    if (poolLeavesJson) {
      this.poolRebalanceLeaves = JSON.parse(poolLeavesJson);
      console.log('Loaded pool rebalance leaves from Redis:', this.poolRebalanceLeaves.length);
    }
    console.log('🚀 DataWorker service started');
    // Initialize last processed blocks
    this.lastProcessedBlockA = await this.providerA.getBlockNumber() - 15600;
    this.lastProcessedBlockB = await this.providerB.getBlockNumber() - 15600;
    this.isRunning = true;
    // Start polling for events
    this.startPolling();
    // Start bundle proposal monitoring
    this.startBundleMonitoring();
  }

  private async startPolling() {
    const pollChainA = async () => {
      if (!this.isRunning) return;
      
      try {
        await this.pollForEvents('A', this.spokePoolA, this.providerA);
      } catch (error) {
        console.error('❌ Error polling chain A:', error);
      }
      
      if (this.isRunning) {
        setTimeout(pollChainA, this.pollingInterval);
      }
    };

    const pollChainB = async () => {
      if (!this.isRunning) return;
      
      try {
        await this.pollForEvents('B', this.spokePoolB, this.providerB);
      } catch (error) {
        console.error('❌ Error polling chain B:', error);
      }
      
      if (this.isRunning) {
        setTimeout(pollChainB, this.pollingInterval);
      }
    };

    pollChainA();
    pollChainB();
  }

  private async startBundleMonitoring() {
    const monitorBundle = async () => {
      if (!this.isRunning) return;
      
      try {
        await this.checkAndExecuteBundle();
      } catch (error) {
        console.error('❌ Error monitoring bundle:', error);
      }
      
      if (this.isRunning) {
        setTimeout(monitorBundle, this.pollingInterval * 2); // Check less frequently
      }
    };

    monitorBundle();
  }

  private async pollForEvents(
    chainLabel: string, 
    spokePool: ethers.Contract, 
    provider: ethers.JsonRpcProvider
  ) {
    const currentBlock = await provider.getBlockNumber();
    const lastProcessedBlock = chainLabel === 'A' ? this.lastProcessedBlockA : this.lastProcessedBlockB;
    
    if (currentBlock <= lastProcessedBlock) {
      return;
    }

    const fromBlock = lastProcessedBlock + 1;
    const toBlock = Math.min(fromBlock + this.blockRange - 1, currentBlock);

    console.log(`🔍 Polling chain ${chainLabel} from block ${fromBlock} to ${toBlock}`);
    
    try {
      const eventTopic = '0x44b559f101f8fbcc8a0ea43fa91a05a729a5ea6e14a7c75aa750374690137208'; // FilledRelay

      const nonIndexedTypes = [
        'bytes32',  // inputToken
        'bytes32',  // outputToken
        'uint256',  // inputAmount
        'uint256',  // outputAmount
        'uint256',  // repaymentChainId
        'uint32',   // fillDeadline
        'uint32',   // exclusivityDeadline
        'bytes32',  // exclusiveRelayer
        'bytes32',  // depositor
        'bytes32',  // recipient
        'bytes32',  // messageHash
        'tuple(bytes32 updatedRecipient, bytes32 updatedMessageHash, uint256 updatedOutputAmount, uint8 fillType)'
      ];

      const filter = {
        address: spokePool.target,
        fromBlock,
        toBlock,
        topics: [eventTopic]
      };

      const logs = await provider.getLogs(filter);
      const abiCoder = ethers.AbiCoder.defaultAbiCoder();
    
      for (const log of logs) {
        try {
          const decoded = abiCoder.decode(nonIndexedTypes, log.data);
          
          const relayEntry: RelayData = {
            chain: chainLabel,
            inputToken: decoded[0].toString(),
            outputToken: decoded[1].toString(),
            inputAmount: decoded[2].toString(),
            outputAmount: decoded[3].toString(),
            repaymentChainId: decoded[4].toString(),
            originChainId: BigInt(log.topics[1]).toString(),
            depositId: BigInt(log.topics[2]).toString(),
            relayer: log.topics[3],
            timestamp: Date.now(),
            blockNumber: log.blockNumber,
            transactionHash: log.transactionHash
          };
          console.log('✅ FilledRelay log decoded:', relayEntry);
        
          this.relayData.push(relayEntry);
          
          // Process refund for this relay
          await this.processRelayForRefund(relayEntry);
          
          console.log(`✅ Processed FilledRelay on chain ${chainLabel}, deposit ${relayEntry.depositId}`);
        } catch (err) {
          console.warn('❌ Failed to decode log:', err);
        }
      }

      // Update last processed block
      if (chainLabel === 'A') {
        this.lastProcessedBlockA = toBlock;
      } else {
        this.lastProcessedBlockB = toBlock;
      }

      await this.redis.set(`lastProcessedBlock_${chainLabel}`, toBlock.toString());
    } catch (error) {
      console.error(`❌ Error querying events for chain ${chainLabel}:`, error);
    }
  }

  private async processRelayForRefund(relay: RelayData) {
    const relayerAddress = relay.relayer;
    const repaymentChainId = parseInt(relay.repaymentChainId);
    
    // Create refund entry for the relayer
    const refund: RelayerRefund = {
      relayer: relayerAddress,
      token: relay.outputToken,
      amount: relay.outputAmount,
      chainId: repaymentChainId,
      refundCounter: this.refundCounter++
    };

    // Group refunds by relayer
    if (!this.relayerRefunds.has(relayerAddress)) {
      this.relayerRefunds.set(relayerAddress, []);
    }
    this.relayerRefunds.get(relayerAddress)!.push(refund);

    // Store in Redis for persistence
    await this.redis.hSet(
      `refunds:${relayerAddress}`,
      `${refund.chainId}:${refund.refundCounter}`,
      JSON.stringify(refund)
    );

    console.log(`💰 Queued refund for relayer ${relayerAddress}: ${ethers.formatEther(refund.amount)} tokens on chain ${repaymentChainId}`);
  }

  private async shouldProposeBundle(): Promise<boolean> {
    // Check if we have enough volume to justify proposing a bundle
    let totalRefundVolume = 0n;
    
    for (const [relayer, refunds] of this.relayerRefunds) {
      for (const refund of refunds) {
        totalRefundVolume += BigInt(refund.amount);
      }
    }

    console.log(`📊 Total refund volume: ${ethers.formatEther(totalRefundVolume)} ETH equivalent`);
    
    return totalRefundVolume >= this.minRefundVolume;
  }

  bytes32ToAddress(bytes32: any) {
    return ethers.getAddress('0x' + bytes32.slice(-40));
  }

  // private async buildRelayerRefundRoot(): Promise<string> {
  //   const leaves: string[] = [];
  //   this.relayerRefundLeaves = []; // Reset leaves
    
  //   // Group refunds by chain and token
  //   const refundsByChainAndToken = new Map<string, Map<string, RelayerRefund[]>>();
    
  //   for (const [relayer, refunds] of this.relayerRefunds) {
  //     for (const refund of refunds) {
  //       const chainKey = refund.chainId.toString();
  //       const tokenKey = refund.token;
        
  //       if (!refundsByChainAndToken.has(chainKey)) {
  //         refundsByChainAndToken.set(chainKey, new Map());
  //       }
        
  //       if (!refundsByChainAndToken.get(chainKey)!.has(tokenKey)) {
  //         refundsByChainAndToken.get(chainKey)!.set(tokenKey, []);
  //       }
        
  //       refundsByChainAndToken.get(chainKey)!.get(tokenKey)!.push(refund);
  //     }
  //   }
    
  //   // Create RefundLeaf for each chain/token combination
  //   let leafId = 0;
  //   for (const [chainId, tokenMap] of refundsByChainAndToken) {
  //     for (const [token, refunds] of tokenMap) {
  //       // const refundAddresses = refunds.map(r => r.relayer);
  //       const refundAddresses = refunds.map(r => this.bytes32ToAddress(r.relayer));
        
  //       const refundAmounts = refunds.map(r => r.amount);
  //       const totalAmount = refundAmounts.reduce((sum, amount) => sum + BigInt(amount), 0n);
        
  //       const refundLeaf: RelayerRefundLeaf = {
  //         amountToReturn: totalAmount.toString(),
  //         chainId: parseInt(chainId),
  //         refundAmounts: refundAmounts,
  //         leafId: leafId++,
  //         l2TokenAddress: this.bytes32ToAddress(token),
  //         refundAddresses: refundAddresses
  //       };
        
  //       // LOGGING for debugging
  //       console.log('--- Refund Leaf ---');
  //       console.log('amountToReturn:', refundLeaf.amountToReturn, typeof refundLeaf.amountToReturn);
  //       console.log('chainId:', refundLeaf.chainId, typeof refundLeaf.chainId);
  //       console.log('refundAmounts:', refundLeaf.refundAmounts, refundLeaf.refundAmounts.map(a => typeof a));
  //       console.log('leafId:', refundLeaf.leafId, typeof refundLeaf.leafId);
  //       console.log('l2TokenAddress:', refundLeaf.l2TokenAddress, typeof refundLeaf.l2TokenAddress);
  //       console.log('refundAddresses:', refundLeaf.refundAddresses, refundLeaf.refundAddresses.map(a => typeof a));
  //       // Check address formatting
  //       refundLeaf.refundAddresses.forEach((addr, i) => {
  //         console.log(`refundAddress[${i}]:`, addr, 'length:', addr.length);
  //       });
  //       console.log('-------------------');
        
  //       this.relayerRefundLeaves.push(refundLeaf);

  //       console.log('Relayer refund leaves: ', this.relayerRefundLeaves);

  //       // Create leaf hash
  //       const leafData = ethers.AbiCoder.defaultAbiCoder().encode(
  //         ['uint256', 'uint256', 'uint256[]', 'uint32', 'address', 'address[]'],
  //         [
  //           refundLeaf.amountToReturn,
  //           refundLeaf.chainId,
  //           refundLeaf.refundAmounts,
  //           refundLeaf.leafId,
  //           refundLeaf.l2TokenAddress,
  //           refundLeaf.refundAddresses
  //         ]
  //       );
  //       leaves.push(ethers.keccak256(leafData));
  //       console.log('Leaves: ', leaves);
  //     }
  //   }
    
  //   if (leaves.length === 0) {
  //     return ethers.ZeroHash;
  //   }
    
  //   const merkleTree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
  //   return merkleTree.getHexRoot();
  // }

  private async buildRelayerRefundRoot(): Promise<string> {
    this.relayerRefundLeaves = []; 
    const leaves: RelayerRefundLeaf[] = [];
  
    // Group refunds by chain and token
    const refundsByChainAndToken = new Map<string, Map<string, RelayerRefund[]>>();
  
    for (const [relayer, refunds] of this.relayerRefunds) {
      for (const refund of refunds) {
        const chainKey = refund.chainId.toString();
        const tokenKey = refund.token;
  
        if (!refundsByChainAndToken.has(chainKey)) {
          refundsByChainAndToken.set(chainKey, new Map());
        }
  
        if (!refundsByChainAndToken.get(chainKey)!.has(tokenKey)) {
          refundsByChainAndToken.get(chainKey)!.set(tokenKey, []);
        }
  
        refundsByChainAndToken.get(chainKey)!.get(tokenKey)!.push(refund);
      }
    }
  
    // Create RefundLeaf for each chain/token combination
    let leafId = 0;
    for (const [chainId, tokenMap] of refundsByChainAndToken) {
      for (const [token, refunds] of tokenMap) {
        const refundAddresses = refunds.map(r => this.bytes32ToAddress(r.relayer));
        const refundAmounts = refunds.map(r => r.amount);
        const totalAmount = refundAmounts.reduce((sum, amount) => sum + BigInt(amount), 0n);
  
        const refundLeaf: RelayerRefundLeaf = {
          amountToReturn: totalAmount.toString(),
          chainId: parseInt(chainId),
          refundAmounts: refundAmounts,
          leafId: leafId++,
          l2TokenAddress: this.bytes32ToAddress(token),
          refundAddresses: refundAddresses
        };
  
        console.log('--- Refund Leaf ---');
        console.log('Leaf:', refundLeaf);
        console.log('-------------------');
  
        this.relayerRefundLeaves.push(refundLeaf);
        leaves.push(refundLeaf); 
      }
    }
  
    if (leaves.length === 0) {
      return ethers.ZeroHash;
    }
  
    const merkleTree = this.createRelayerRefundMerkleTree(leaves);
    return merkleTree.getHexRoot();
  }
  

  private async processRelayData() {
    // Only propose a bundle if there is at least one FilledRelay event AND no active bundle proposal
    // const bundleProposal = await this.hubPool.rootBundleProposal();
    // const hasActiveProposal = bundleProposal.unclaimedPoolRebalanceLeafCount && bundleProposal.unclaimedPoolRebalanceLeafCount > 0n;
    // if (this.relayData.length === 0 || hasActiveProposal) {
    //   if (this.relayData.length === 0) {
    //     console.log('⏳ No FilledRelay events observed, not proposing bundle yet.');
    //   }
    //   if (hasActiveProposal) {
    //     console.log('⏳ Active bundle proposal exists, not proposing new bundle.');
    //   }
    //   return;
    // }
    
    console.log('🏗️  Building bundle for proposal...');

    try {
      const currentBlockA = await this.providerA.getBlockNumber();
      const currentBlockB = await this.providerB.getBlockNumber();
      
      const bundleEvaluationBlockNumbers = [currentBlockA, currentBlockB];
      
      const poolRebalanceRoot = await this.buildPoolRebalanceRoot();
      const relayerRefundRoot = await this.buildRelayerRefundRoot();
      const slowRelayRoot = ethers.ZeroHash; // Not handling slow relays
      
      console.log('📄 Refund Bundle:');
      console.log('  - Pool Rebalance root:', poolRebalanceRoot);
      console.log('  - Relayer refund root:', relayerRefundRoot);
      console.log('  - Total refund leaves:', this.relayerRefundLeaves.length);
      console.log('  - Evaluation blocks:', bundleEvaluationBlockNumbers);
      
      // const tx = await this.hubPool.proposeRootBundle(
      //   bundleEvaluationBlockNumbers,
      //   2, 
      //   poolRebalanceRoot, 
      //   relayerRefundRoot,
      //   ethers.ZeroHash // No slow relay root
      // );
      
      // await tx.wait();
      // console.log(`✅ Relayer refund bundle proposed: ${tx.hash}`);
      
      // Store bundle info in Redis
      await this.redis.set('lastBundleProposal', JSON.stringify({
        // transactionHash: tx.hash,
        timestamp: Date.now(),
        relayerRefundRoot,
        refundLeafCount: this.relayerRefundLeaves.length
      }));
      
      // Persist relayer refund leaves in Redis
      await this.redis.set('lastRelayerRefundLeaves', JSON.stringify(this.relayerRefundLeaves));
      await this.redis.set('lastPoolRebalanceLeaves', JSON.stringify(this.poolRebalanceLeaves));
 
      // Clear processed data
      this.relayData = [];
      this.relayerRefunds.clear();
      
    } catch (error) {
      console.error('❌ Error proposing bundle:', error);
    }
  }

  private async checkAndExecuteBundle() {
    try {
      console.log("relay data length", this.relayData.length)
      // If there is new relay data, process it first and return
      // if (this.relayData.length > 0) {
      // await this.processRelayData();
      //   return;
      // }
      
      const bundleProposal = await this.hubPool.rootBundleProposal();
      console.log("bundle proposal", bundleProposal);
      // If there is no bundle proposal, propose a new one
      // if (!bundleProposal.challengePeriodEndTimestamp || bundleProposal.challengePeriodEndTimestamp === 0n) {
      if (bundleProposal.unclaimedPoolRebalanceLeafCount == 0n) {
        console.log('No bundle proposal exists, proposing new bundle...');
        await this.processRelayData();
        return;
      }
      const currentTime = await this.hubPool.getCurrentTime();
      const liveness = await this.hubPool.liveness();
     
      
      // Check if challenge period has passed
      if (bundleProposal.challengePeriodEndTimestamp > 0n && 
          currentTime >= bundleProposal.challengePeriodEndTimestamp) {
        
        console.log('⏰ Challenge period ended, bundle can be executed');
        
        // In a full implementation, you would:
        // 1. Generate merkle proofs for each refund leaf
        // 2. Execute refunds on spoke pools
        // 3. Execute pool rebalancing
        // await this.executeRootBundleOnHubPool(); 
        // Execute refunds on spoke pools
        await this.executeRefundsOnSpokePool(this.spokePoolA, parseInt(config.chainA.chainId.toString()));
        await this.executeRefundsOnSpokePool(this.spokePoolB, parseInt(config.chainB.chainId.toString()));
        
        console.log('✅ Bundle execution completed');
        
        // Trigger new bundle proposal if we have more data
        if (this.relayData.length > 0) {
          await this.processRelayData();
        }
      } else if (bundleProposal.challengePeriodEndTimestamp > 0n) {
        const timeRemaining = bundleProposal.challengePeriodEndTimestamp - currentTime;
        console.log(`⏳ Challenge period active, ${timeRemaining} seconds remaining`);
      }
    } catch (error) {
      console.error('❌ Error checking bundle status:', error);
    }
  }

  private async executeRootBundleOnHubPool() {
    console.log('🏗️ Executing root bundle on HubPool...');
    
    try {
      // Get the current bundle proposal to get the actual pool rebalance root
      const bundleProposal = await this.hubPool.rootBundleProposal();
      console.log('Bundle proposal pool rebalance root:', bundleProposal.poolRebalanceRoot);
      
      // Create pool rebalance leaves for each chain
      const chainIds = [config.chainA.chainId, config.chainB.chainId];
      const poolRebalanceLeaves = [];
      
      for (let i = 0; i < chainIds.length; i++) {
        const leaf = {
          chainId: chainIds[i],
          bundleLpFees: [], // Empty for relayer refunds only
          netSendAmounts: [], // Empty for relayer refunds only  
          runningBalances: [], // Empty for relayer refunds only
          groupIndex: 0,
          leafId: i, // Use chain index as leaf ID
          l1Tokens: [] // Empty for relayer refunds only
        };
        poolRebalanceLeaves.push(leaf);
      }
      console.log("poolooooo: ", poolRebalanceLeaves); 
      // Generate merkle tree from the leaves
      const merkleTree = this.createPoolRebalanceMerkleTree(poolRebalanceLeaves);
      console.log('Generated pool rebalance root:', merkleTree.getHexRoot());
      console.log('Expected pool rebalance root:', bundleProposal.poolRebalanceRoot);
      
      // Verify the roots match
      if (merkleTree.getHexRoot() !== bundleProposal.poolRebalanceRoot) {
        throw new Error(`Pool rebalance root mismatch. Generated: ${merkleTree.getHexRoot()}, Expected: ${bundleProposal.poolRebalanceRoot}`);
      }
      
      // Execute each leaf
      for (const leaf of poolRebalanceLeaves) {
        const proof = this.generatePoolRebalanceProofForLeaf(merkleTree, leaf);
        try {
          console.log(`Executing root bundle for chain ${leaf.chainId}...`);
          console.log('Leaf data:', leaf);
          console.log('Proof:', proof);

          const tx = await this.hubPool.executeRootBundle(
            leaf.chainId,
            leaf.groupIndex,
            leaf.bundleLpFees,
            leaf.netSendAmounts,
            leaf.runningBalances,
            leaf.leafId,
            leaf.l1Tokens,
            proof
          );
          await tx.wait();
          console.log(`✅ Root bundle executed for chain ${leaf.chainId}: ${tx.hash}`);
        } catch (error: any) {
          // If error is 'Already claimed', log and continue
          if (error && error.reason && error.reason.includes('Already claimed')) {
            console.warn(`⚠️ Leaf for chain ${leaf.chainId} already claimed, skipping.`);
            continue;
          }
          // Otherwise, rethrow
          console.error(`❌ Error executing root bundle for chain ${leaf.chainId}:`, error);
        }
      }
      
      console.log('✅ All root bundles executed, roots relayed to spoke pools');
      
    } catch (error) {
      console.error('❌ Error executing root bundle:', error);
      throw error;
    }
  }
  // private async executeRootBundleOnHubPool() {
  //   console.log('🏗️ Executing root bundle on HubPool...');
    
  //   try {
  //     // Load the stored pool rebalance leaves that were used in the original proposal
  //     const storedLeaves = await this.redis.get('lastPoolRebalanceLeaves');
  //     if (!storedLeaves) {
  //       throw new Error('No stored pool rebalance leaves found');
  //     }
      
  //     const poolRebalanceLeaves: PoolRebalanceLeaf[] = JSON.parse(storedLeaves);
  //     console.log('Loaded pool rebalance leaves:', poolRebalanceLeaves.length);
      
  //     // Verify we have the right leaves by checking the root
  //     const merkleTree = this.createPoolRebalanceMerkleTree(poolRebalanceLeaves);
  //     const bundleProposal = await this.hubPool.rootBundleProposal();
      
  //     console.log('Generated pool rebalance root:', merkleTree.getHexRoot());
  //     console.log('Expected pool rebalance root:', bundleProposal.poolRebalanceRoot);
      
  //     if (merkleTree.getHexRoot() !== bundleProposal.poolRebalanceRoot) {
  //       throw new Error(`Pool rebalance root mismatch. Generated: ${merkleTree.getHexRoot()}, Expected: ${bundleProposal.poolRebalanceRoot}`);
  //     }
      
  //     // Execute each leaf in the correct order
  //     for (const leaf of poolRebalanceLeaves) {
  //       const proof = this.generatePoolRebalanceProofForLeaf(merkleTree, leaf);
        
  //       console.log(`Executing root bundle for chain ${leaf.chainId}...`);
  //       console.log('Leaf:', leaf);
  //       console.log('Proof:', proof);
        
  //       const tx = await this.hubPool.executeRootBundle(
  //         leaf.chainId,
  //         leaf.groupIndex,
  //         leaf.bundleLpFees,
  //         leaf.netSendAmounts,
  //         leaf.runningBalances,
  //         leaf.leafId,
  //         leaf.l1Tokens,
  //         proof
  //       );
        
  //       await tx.wait();
  //       console.log(`✅ Root bundle executed for chain ${leaf.chainId}: ${tx.hash}`);
  //     }
      
  //     console.log('✅ All root bundles executed, roots relayed to spoke pools');
      
  //   } catch (error) {
  //     console.error('❌ Error executing root bundle:', error);
  //     throw error;
  //   }
  // }
  
  
  private createPoolRebalanceMerkleTree(leaves: any[]): MerkleTree {
    const leafHashes = leaves.map(leaf => this.hashPoolRebalanceLeaf(leaf));
    return new MerkleTree(leafHashes, ethers.keccak256, { sortPairs: true });
  }
  
  // private hashPoolRebalanceLeaf(leaf: any): string {
  //   // This should match the leaf hashing logic in the HubPool contract
  //   // The contract likely uses a specific encoding for PoolRebalanceLeaf
  //   const leafData = ethers.AbiCoder.defaultAbiCoder().encode(
  //     ['uint256', 'uint256[]', 'int256[]', 'int256[]', 'uint256', 'uint8', 'address[]'],
  //     // [
  //     //   leaf.chainId,
  //     //   leaf.bundleLpFees,
  //     //   leaf.netSendAmounts,
  //     //   leaf.runningBalances,
  //     //   leaf.groupIndex,
  //     //   leaf.leafId,
  //     //   leaf.l1Tokens
  //     // ]
  //     [
  //       BigInt(leaf.chainId),
  //       leaf.bundleLpFees.map(BigInt),
  //       leaf.netSendAmounts.map(BigInt),
  //       leaf.runningBalances.map(BigInt),
  //       BigInt(leaf.groupIndex),
  //       Number(leaf.leafId),
  //       leaf.l1Tokens
  //     ]
  //   );
  //   return ethers.keccak256(leafData);
  // }

  private hashPoolRebalanceLeaf(leaf: PoolRebalanceLeaf): string {
    const cleanedLeaf = {
      chainId: BigInt(leaf.chainId),
      bundleLpFees: (leaf.bundleLpFees || []).map(BigInt),
      netSendAmounts: (leaf.netSendAmounts || []).map(BigInt),
      runningBalances: (leaf.runningBalances || []).map(BigInt),
      groupIndex: BigInt(leaf.groupIndex),
      leafId: Number(leaf.leafId),
      l1Tokens: (leaf.l1Tokens || []).map(addr => ethers.getAddress(addr))
    };
  
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      [
        "tuple(" +
          "uint256 chainId," +
          "uint256[] bundleLpFees," +
          "int256[] netSendAmounts," +
          "int256[] runningBalances," +
          "uint256 groupIndex," +
          "uint8 leafId," +
          "address[] l1Tokens" +
        ")"
      ],
      [cleanedLeaf]
    );
    
  
    const hash = ethers.keccak256(encoded);
  
    // console.log("Leaf struct:", cleanedLeaf);
    // console.log("Encoded:", encoded);
    console.log("Leaf hash:", hash);
  
    return hash;
  }
  
  
  private generatePoolRebalanceProofForLeaf(merkleTree: MerkleTree, leaf: any): string[] {
    const leafHash = this.hashPoolRebalanceLeaf(leaf);
    return merkleTree.getHexProof(leafHash);
  }
  
  private async buildPoolRebalanceRoot(): Promise<string> {
    // Create minimal pool rebalance leaves for each chain to enable root relay
    const chainIds = [config.chainA.chainId, config.chainB.chainId];
    this.poolRebalanceLeaves = [];
    
    for (let i = 0; i < chainIds.length; i++) {
      const leaf = {
        chainId: chainIds[i],
        bundleLpFees: [], // empty for refund-only bundles
        netSendAmounts: [], // empty for refund-only bundles
        runningBalances: [], // empty for refund-only bundles
        groupIndex: 0, // groupIndex 0 triggers root relay
        leafId: i, // leafId
        l1Tokens: [] // empty for refund-only bundles
      };
      this.poolRebalanceLeaves.push(leaf);
      console.log('PoolRebalanceLeaf:', leaf);
    }
    
    if (this.poolRebalanceLeaves.length === 0) {
      return ethers.ZeroHash;
    }
    
    const merkleTree = this.createPoolRebalanceMerkleTree(this.poolRebalanceLeaves);
    return merkleTree.getHexRoot();
  }

  // private hashRelayerRefundLeaf(leaf: RelayerRefundLeaf): string {
  //   const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
  //     [
  //       "tuple(" +
  //         "uint256 amountToReturn," +
  //         "uint256 chainId," +
  //         "uint256[] refundAmounts," +
  //         "uint32 leafId," +
  //         "address l2TokenAddress," +
  //         "address[] refundAddresses" +
  //       ")"
  //     ],
  //     [leaf]
  //   );
  //   const hash = ethers.keccak256(encoded);
  //   console.log("RelayerRefundLeaf hash:", hash);
  //   return hash;
  // }

  private hashRelayerRefundLeaf(leaf: RelayerRefundLeaf): string {
    const cleanedLeaf = {
      amountToReturn: BigInt(leaf.amountToReturn),
      chainId: BigInt(leaf.chainId),
      refundAmounts: (leaf.refundAmounts || []).map(BigInt),
      leafId: leaf.leafId,
      l2TokenAddress: ethers.getAddress(leaf.l2TokenAddress),
      refundAddresses: (leaf.refundAddresses || []).map(addr => ethers.getAddress(addr))
    };
  
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      [
        "tuple(" +
          "uint256 amountToReturn," +
          "uint256 chainId," +
          "uint256[] refundAmounts," +
          "uint32 leafId," +
          "address l2TokenAddress," +
          "address[] refundAddresses" +
        ")"
      ],
      [cleanedLeaf]
    );
  
    const hash = ethers.keccak256(encoded);
    console.log("RelayerRefundLeaf hash:", hash);
  
    return hash;
  }


  private createRelayerRefundMerkleTree(leaves: any[]): MerkleTree {
    const leafHashes = leaves.map(leaf => this.hashRelayerRefundLeaf(leaf));
    return new MerkleTree(leafHashes, ethers.keccak256, { sortPairs: true });
  }
  

  async executeRefundsOnSpokePool(spokePool: ethers.Contract, chainId: number) {
    // Fetch the latest rootBundleId from the SpokePool
    let rootBundleId = 0;
    try {
      // Try to get the length of rootBundles array by incrementing until revert
      // (If SpokePool exposes a length() or rootBundlesLength() view, use that instead)
      let found = true;
      while (found) {
        try {
          // Try to fetch the next rootBundle
          await spokePool.rootBundles(rootBundleId);
          rootBundleId++;
        } catch (err) {
          found = false;
        }
      }
      if (rootBundleId > 0) rootBundleId = rootBundleId - 1;
    } catch (err) {
      rootBundleId = 0;
    }
    console.log(`Using rootBundleId ${rootBundleId} for chain ${chainId}`);

    // Filter refund leaves for this chain
    const chainRefunds = this.relayerRefundLeaves.filter(leaf => leaf.chainId === chainId);
    
    if (chainRefunds.length === 0) {
      console.log(`No refunds to execute on chain ${chainId}`);
      return;
    }
    
    console.log(`💸 Executing ${chainRefunds.length} refund leaves on chain ${chainId}`);
    
    // Build merkle tree for proof generation
    const leaves = this.relayerRefundLeaves.map(leaf => {
      const leafData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'uint256', 'uint256[]', 'uint32', 'address', 'address[]'],
        [
          leaf.amountToReturn,
          leaf.chainId,
          leaf.refundAmounts,
          leaf.leafId,
          leaf.l2TokenAddress,
          leaf.refundAddresses
        ]
      );
      return ethers.keccak256(leafData);
    });
    console.log("leaves", leaves) 
    const merkleTree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
    
    for (const refundLeaf of chainRefunds) {
      try {
        console.log("refund leaf data", refundLeaf)
        // Generate merkle proof
        const leafData = ethers.AbiCoder.defaultAbiCoder().encode(
          ['uint256', 'uint256', 'uint256[]', 'uint32', 'address', 'address[]'],
          [
            refundLeaf.amountToReturn,
            refundLeaf.chainId,
            refundLeaf.refundAmounts,
            refundLeaf.leafId,
            refundLeaf.l2TokenAddress,
            refundLeaf.refundAddresses
          ]
        );
        console.log("refund leaf hashed data: ", leafData);
        const leafHash = ethers.keccak256(leafData);
        console.log("Leaf hash", leafHash);
        const proof = merkleTree.getHexProof(leafHash);
        console.log('Calling executeRelayerRefundLeaf with:', {
          leafId: refundLeaf.leafId,
          proof,
          tuple: [
            refundLeaf.amountToReturn,
            refundLeaf.chainId,
            refundLeaf.refundAmounts,
            refundLeaf.leafId,
            refundLeaf.l2TokenAddress,
            refundLeaf.refundAddresses
          ]
        });
        if (refundLeaf.refundAmounts.length !== refundLeaf.refundAddresses.length) {
          throw new Error(`Mismatch in refundAmounts (${refundLeaf.refundAmounts.length}) and refundAddresses (${refundLeaf.refundAddresses.length})`);
        }
        console.log('Refund amounts:', refundLeaf.refundAmounts);
        console.log('Refund addresses:', refundLeaf.refundAddresses);
        const refundAmounts = refundLeaf.refundAmounts.map(amount => 
          typeof amount === 'string' ? BigInt(amount) : amount
        );
        const tx = await spokePool.executeRelayerRefundLeaf(
          1, //FIXME: Hardcoding only for testing purpose
          {
            amountToReturn: BigInt(refundLeaf.amountToReturn),
            chainId: refundLeaf.chainId,
            refundAmounts: refundAmounts,
            leafId: refundLeaf.leafId,
            l2TokenAddress: refundLeaf.l2TokenAddress,
            refundAddresses: refundLeaf.refundAddresses
          },
          proof
        );
        
        await tx.wait();
        console.log(`✅ Executed refund leaf ${refundLeaf.leafId} on chain ${chainId}: ${tx.hash}`);
        
        // Log individual refunds
        for (let i = 0; i < refundLeaf.refundAddresses.length; i++) {
          console.log(`  - Refunded ${ethers.formatEther(refundLeaf.refundAmounts[i])} to ${refundLeaf.refundAddresses[i]}`);
        }
        
      } catch (error) {
        console.error(`❌ Failed to execute refund leaf ${refundLeaf.leafId}:`, error);
      }
    }
    // After all refunds executed, clear the stored leaves
    await this.redis.del('lastRelayerRefundLeaves');
  }

  async stop() {
    this.isRunning = false;
    await this.redis.disconnect();
    console.log('🛑 DataWorker stopped');
  }
}

const config: DataWorkerConfig = {
  hubPool: {
    rpc: process.env.HUBPOOL_RPC!,
    privateKey: process.env.HUBPOOL_PRIVATE_KEY!,
    address: process.env.HUBPOOL_ADDRESS!
  },
  chainA: {
    rpc: process.env.CHAIN_A_RPC!,
    spokePoolAddress: process.env.SPOKEPOOL_A_ADDRESS!,
    chainId: parseInt(process.env.CHAIN_A_ID!)
  },
  chainB: {
    rpc: process.env.CHAIN_B_RPC!,
    spokePoolAddress: process.env.SPOKEPOOL_B_ADDRESS!,
    chainId: parseInt(process.env.CHAIN_B_ID!)
  },
  redisUrl: process.env.REDIS_URL!,
  pollingInterval: 10000,
  minRefundVolume: "100" // 100 ETH equivalent before proposing bundle
};

const dataWorker = new AcrossDataWorker(config);

// Handle graceful shutdown
process.on('SIGINT', async () => {
  console.log('Received SIGINT, shutting down gracefully...');
  await dataWorker.stop();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  await dataWorker.stop();
  process.exit(0);
});

dataWorker.start().catch(console.error);