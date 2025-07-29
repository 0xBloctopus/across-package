import { ethers } from 'ethers';
import { createClient, RedisClientType} from 'redis';
import { MerkleTree } from 'merkletreejs';
import { BigNumberish } from "ethers";
import 'dotenv/config'; 

interface ChainConfig {
  chainId: number;
  type: string;
  rpc: string;
  spokePoolAddress: string;
}

interface DataWorkerConfig {
  hubPool: { rpc: string; privateKey: string; address: string };
  chains: ChainConfig[];
  redisUrl: string;
  pollingInterval?: number;
  blockRange?: number;
  minRefundVolume?: string;
}

interface RelayData {
  chainId: number;
  chainName: string;
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

interface ChainWorker {
  chainId: number;
  type: string;
  provider: ethers.JsonRpcProvider;
  wallet: ethers.Wallet;
  spokePool: ethers.Contract;
  lastProcessedBlock: number;
}

class MultiChainAcrossDataWorker {
  private hubPoolProvider: ethers.JsonRpcProvider;
  private hubPoolWallet: ethers.Wallet;
  private hubPool: ethers.Contract;
  private chainWorkers: Map<number, ChainWorker> = new Map();
  private redis: RedisClientType;
  private relayData: RelayData[] = [];
  private relayerRefunds: Map<string, RelayerRefund[]> = new Map();
  private relayerRefundLeaves: RelayerRefundLeaf[] = [];
  private poolRebalanceLeaves: PoolRebalanceLeaf[] = [];
  private pollingInterval: number;
  private isRunning: boolean = false;
  private blockRange: number;
  private minRefundVolume: bigint;
  private refundCounter: number = 0;
  private config: DataWorkerConfig;

  constructor(config: DataWorkerConfig) {
    this.config = config;
    this.hubPoolProvider = new ethers.JsonRpcProvider(config.hubPool.rpc);
    this.hubPoolWallet = new ethers.Wallet(config.hubPool.privateKey, this.hubPoolProvider);
    
    const hubPoolAbi = [
      "function proposeRootBundle(uint256[] calldata bundleEvaluationBlockNumbers, uint8 poolRebalanceLeafCount, bytes32 poolRebalanceRoot, bytes32 relayerRefundRoot, bytes32 slowRelayRoot)",
      "function getCurrentTime() view returns (uint256)",
      "function liveness() view returns (uint32)",
      "function rootBundleProposal() view returns (bytes32 poolRebalanceRoot, bytes32 relayerRefundRoot, bytes32 slowRelayRoot, uint256 claimedBitMap, address proposer, uint8 unclaimedPoolRebalanceLeafCount, uint32 challengePeriodEndTimestamp)",
      "function executeRootBundle(uint256 chainId, uint256 groupIndex, uint256[] memory bundleLpFees, int256[] memory netSendAmounts, int256[] memory runningBalances, uint8 leafId, address[] memory l1Tokens, bytes32[] memory proof)"
    ];
    this.hubPool = new ethers.Contract(config.hubPool.address, hubPoolAbi, this.hubPoolWallet);
    
    // Initialize chain workers
    this.initializeChainWorkers();
    
    this.redis = createClient({ url: config.redisUrl });
    this.pollingInterval = config.pollingInterval || 15000;
    this.blockRange = config.blockRange || 100;
    this.minRefundVolume = ethers.parseEther("0");
  }

  private initializeChainWorkers() {
    const spokePoolAbi = [
      "event FilledRelay(bytes32 indexed inputToken, bytes32 indexed outputToken, uint256 inputAmount, uint256 outputAmount, uint256 repaymentChainId, uint256 indexed originChainId, uint256 indexed depositId, uint32 fillDeadline, uint32 exclusivityDeadline, bytes32 exclusiveRelayer, bytes32 indexed relayer, bytes32 depositor, bytes32 recipient, bytes32 messageHash, tuple(bytes32 updatedRecipient, bytes32 updatedMessageHash,uint256 updatedOutputAmount, uint8 fillType) relayExecutionInfo)",
      "function executeRelayerRefundLeaf(uint32 rootBundleId, tuple(uint256 amountToReturn, uint256 chainId, uint256[] refundAmounts, uint32 leafId, address l2TokenAddress, address[] refundAddresses), bytes32[] memory proof)",
    ];

    for (const chainConfig of this.config.chains) {
      const provider = new ethers.JsonRpcProvider(chainConfig.rpc);
      const wallet = new ethers.Wallet(this.config.hubPool.privateKey, provider);
      const spokePool = new ethers.Contract(chainConfig.spokePoolAddress, spokePoolAbi, wallet);

      const chainWorker: ChainWorker = {
        chainId: chainConfig.chainId,
        type: chainConfig.type,
        provider,
        wallet,
        spokePool,
        lastProcessedBlock: 0
      };

      this.chainWorkers.set(chainConfig.chainId, chainWorker);
      console.log(`✅ Initialized chain worker for ${chainConfig.type} (Chain ID: ${chainConfig.chainId})`);
    }
  }

  async start() {
    await this.redis.connect();
    
    // Load state from Redis
    await this.loadStateFromRedis();
    
    console.log(`🚀 Multi-chain DataWorker service started for ${this.chainWorkers.size} chains`);
    
    // Initialize last processed blocks for all chains
    await this.initializeLastProcessedBlocks();
    
    this.isRunning = true;
    
    // Start polling for all chains
    this.startPolling();
    // Start bundle proposal monitoring
    this.startBundleMonitoring();
  }

  private async loadStateFromRedis() {
    // Load relayer refund leaves
    const leavesJson = await this.redis.get('lastRelayerRefundLeaves');
    if (leavesJson) {
      this.relayerRefundLeaves = JSON.parse(leavesJson);
      console.log('Loaded relayer refund leaves from Redis:', this.relayerRefundLeaves.length);
    }
    
    // Load pool rebalance leaves
    const poolLeavesJson = await this.redis.get('lastPoolRebalanceLeaves');
    if (poolLeavesJson) {
      this.poolRebalanceLeaves = JSON.parse(poolLeavesJson);
      console.log('Loaded pool rebalance leaves from Redis:', this.poolRebalanceLeaves.length);
    }
  }

  private async initializeLastProcessedBlocks() {
    for (const [chainId, worker] of this.chainWorkers) {
      // Try to load from Redis first
      const savedBlock = await this.redis.get(`lastProcessedBlock_${chainId}`);
      if (savedBlock) {
        worker.lastProcessedBlock = parseInt(savedBlock);
        console.log(`📚 Loaded last processed block for chain ${chainId}: ${worker.lastProcessedBlock}`);
      } else {
        // Initialize to current block
        worker.lastProcessedBlock = await worker.provider.getBlockNumber();
        console.log(`🔄 Initialized last processed block for chain ${chainId}: ${worker.lastProcessedBlock}`);
      }
    }
  }

  private async startPolling() {
    // Create polling function for each chain
    for (const [chainId, worker] of this.chainWorkers) {
      this.startChainPolling(worker);
    }
  }

  private startChainPolling(worker: ChainWorker) {
    const pollChain = async () => {
      if (!this.isRunning) return;
      
      try {
        await this.pollForEvents(worker);
      } catch (error) {
        console.error(`❌ Error polling chain ${worker.type} (${worker.chainId}):`, error);
      }
      
      if (this.isRunning) {
        setTimeout(pollChain, this.pollingInterval);
      }
    };

    pollChain();
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
        setTimeout(monitorBundle, this.pollingInterval * 2);
      }
    };

    monitorBundle();
  }

  private async pollForEvents(worker: ChainWorker) {
    const currentBlock = await worker.provider.getBlockNumber();
    
    if (currentBlock <= worker.lastProcessedBlock) {
      return;
    }

    const fromBlock = worker.lastProcessedBlock + 1;
    const toBlock = Math.min(fromBlock + this.blockRange - 1, currentBlock);

    console.log(`🔍 Polling chain ${worker.type} (${worker.chainId}) from block ${fromBlock} to ${toBlock}`);
    
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
        address: worker.spokePool.target,
        fromBlock,
        toBlock,
        topics: [eventTopic]
      };

      const logs = await worker.provider.getLogs(filter);
      const abiCoder = ethers.AbiCoder.defaultAbiCoder();
    
      for (const log of logs) {
        try {
          const decoded = abiCoder.decode(nonIndexedTypes, log.data);
          
          const relayEntry: RelayData = {
            chainId: worker.chainId,
            chainName: worker.type,
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
          
          console.log(`✅ FilledRelay event on ${worker.type} (${worker.chainId}):`, relayEntry);
        
          this.relayData.push(relayEntry);
          
          // Process refund for this relay
          await this.processRelayForRefund(relayEntry);
          
          console.log(`✅ Processed FilledRelay on chain ${worker.type}, deposit ${relayEntry.depositId}`);
        } catch (err) {
          console.warn('❌ Failed to decode log:', err);
        }
      }

      // Update last processed block
      worker.lastProcessedBlock = toBlock;
      await this.redis.set(`lastProcessedBlock_${worker.chainId}`, toBlock.toString());
      
    } catch (error) {
      console.error(`❌ Error querying events for chain ${worker.type} (${worker.chainId}):`, error);
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

  private async buildPoolRebalanceRoot(): Promise<string> {
    // Create minimal pool rebalance leaves for each chain
    const chainIds = Array.from(this.chainWorkers.keys());
    this.poolRebalanceLeaves = [];
    
    for (let i = 0; i < chainIds.length; i++) {
      const leaf = {
        chainId: chainIds[i],
        bundleLpFees: [],
        netSendAmounts: [],
        runningBalances: [],
        groupIndex: 0,
        leafId: i,
        l1Tokens: []
      };
      this.poolRebalanceLeaves.push(leaf);
    }
    
    if (this.poolRebalanceLeaves.length === 0) {
      return ethers.ZeroHash;
    }
    
    const merkleTree = this.createPoolRebalanceMerkleTree(this.poolRebalanceLeaves);
    return merkleTree.getHexRoot();
  }

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
    console.log('🏗️  Building bundle for proposal...');

    try {
      // Get current blocks for all chains
      const bundleEvaluationBlockNumbers = [];
      for (const [chainId, worker] of this.chainWorkers) {
        const currentBlock = await worker.provider.getBlockNumber();
        bundleEvaluationBlockNumbers.push(currentBlock);
      }
      
      const poolRebalanceRoot = await this.buildPoolRebalanceRoot();
      const relayerRefundRoot = await this.buildRelayerRefundRoot();
      const slowRelayRoot = ethers.ZeroHash;
      
      console.log('📄 Multi-chain Bundle:');
      console.log('  - Pool Rebalance root:', poolRebalanceRoot);
      console.log('  - Relayer refund root:', relayerRefundRoot);
      console.log('  - Total refund leaves:', this.relayerRefundLeaves.length);
      console.log('  - Evaluation blocks:', bundleEvaluationBlockNumbers);
      console.log('  - Chains covered:', Array.from(this.chainWorkers.keys()));
      
      // Store bundle info in Redis
      await this.redis.set('lastBundleProposal', JSON.stringify({
        timestamp: Date.now(),
        relayerRefundRoot,
        refundLeafCount: this.relayerRefundLeaves.length,
        chainsIncluded: Array.from(this.chainWorkers.keys())
      }));
      
      // Persist leaves in Redis
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
      console.log("Relay data length:", this.relayData.length);
      
      if (this.relayData.length > 0) {
        await this.processRelayData();
        return;
      }
      
      try {
        const bundleProposal = await this.hubPool.rootBundleProposal();
        
        if (bundleProposal.unclaimedPoolRebalanceLeafCount == 0n) {
          console.log('No bundle proposal exists, proposing new bundle...');
          await this.processRelayData();
          return;
        }
        
        const currentTime = await this.hubPool.getCurrentTime();
        
        if (bundleProposal.challengePeriodEndTimestamp > 0n && 
            currentTime >= bundleProposal.challengePeriodEndTimestamp) {
          
          console.log('⏰ Challenge period ended, executing bundle on all chains');
          
          await this.executeRootBundleOnHubPool(); 
          await this.executeRefundsOnAllChains();
          
          console.log('✅ Multi-chain bundle execution completed');
          
          if (this.relayData.length > 0) {
            await this.processRelayData();
          }
        } else if (bundleProposal.challengePeriodEndTimestamp > 0n) {
          const timeRemaining = bundleProposal.challengePeriodEndTimestamp - currentTime;
          console.log(`⏳ Challenge period active, ${timeRemaining} seconds remaining`);
        }
      } catch (hubPoolError: any) {
        if (hubPoolError.code === 'BAD_DATA' || hubPoolError.value === '0x') {
          console.log('⚠️ HubPool contract not accessible, continuing to monitor relay events...');
          return;
        }
        throw hubPoolError;
      }
    } catch (error) {
      console.error('❌ Error checking bundle status:', error);
    }
  }

  private async executeRootBundleOnHubPool() {
    console.log('🏗️ Executing root bundle on HubPool for all chains...');
    
    try {
      const bundleProposal = await this.hubPool.rootBundleProposal();
      const chainIds = Array.from(this.chainWorkers.keys());
      const poolRebalanceLeaves = [];
      
      for (let i = 0; i < chainIds.length; i++) {
        const leaf = {
          chainId: chainIds[i],
          bundleLpFees: [],
          netSendAmounts: [],
          runningBalances: [],
          groupIndex: 0,
          leafId: i,
          l1Tokens: []
        };
        poolRebalanceLeaves.push(leaf);
      }
      
      const merkleTree = this.createPoolRebalanceMerkleTree(poolRebalanceLeaves);
      
      if (merkleTree.getHexRoot() !== bundleProposal.poolRebalanceRoot) {
        throw new Error(`Pool rebalance root mismatch. Generated: ${merkleTree.getHexRoot()}, Expected: ${bundleProposal.poolRebalanceRoot}`);
      }
      
      // Execute for each chain
      for (const leaf of poolRebalanceLeaves) {
        const proof = this.generatePoolRebalanceProofForLeaf(merkleTree, leaf);
        try {
          console.log(`Executing root bundle for chain ${leaf.chainId}...`);

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
          if (error && error.reason && error.reason.includes('Already claimed')) {
            console.warn(`⚠️ Leaf for chain ${leaf.chainId} already claimed, skipping.`);
            continue;
          }
          console.error(`❌ Error executing root bundle for chain ${leaf.chainId}:`, error);
        }
      }
      
    } catch (error) {
      console.error('❌ Error executing root bundle:', error);
      throw error;
    }
  }

  private async executeRefundsOnAllChains() {
    console.log('💸 Executing refunds on all chains...');
    
    for (const [chainId, worker] of this.chainWorkers) {
      try {
        await this.executeRefundsOnSpokePool(worker.spokePool, chainId);
        console.log(`✅ Completed refund execution on ${worker.type} (${chainId})`);
      } catch (error) {
        console.error(`❌ Failed to execute refunds on chain ${chainId}:`, error);
      }
    }
    
    // Clear stored leaves after all executions
    await this.redis.del('lastRelayerRefundLeaves');
  }

  async executeRefundsOnSpokePool(spokePool: ethers.Contract, chainId: number) {
    // Get chain name for logging
    const chainName = this.chainWorkers.get(chainId)?.type || `Chain-${chainId}`;
    
    let rootBundleId = 0;
    try {
      let found = true;
      while (found) {
        try {
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
    console.log(`Using rootBundleId ${rootBundleId} for ${chainName} (${chainId})`);

    const chainRefunds = this.relayerRefundLeaves.filter(leaf => leaf.chainId === chainId);
    
    if (chainRefunds.length === 0) {
      console.log(`No refunds to execute on ${chainName} (${chainId})`);
      return;
    }
    
    console.log(`💸 Executing ${chainRefunds.length} refund leaves on ${chainName} (${chainId})`);
    
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
    
    const merkleTree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
    
    for (const refundLeaf of chainRefunds) {
      try {
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
        
        const leafHash = ethers.keccak256(leafData);
        const proof = merkleTree.getHexProof(leafHash);
        
        if (refundLeaf.refundAmounts.length !== refundLeaf.refundAddresses.length) {
          throw new Error(`Mismatch in refundAmounts and refundAddresses for leaf ${refundLeaf.leafId}`);
        }
        
        const refundAmounts = refundLeaf.refundAmounts.map(amount => 
          typeof amount === 'string' ? BigInt(amount) : amount
        );
        
        const tx = await spokePool.executeRelayerRefundLeaf(
          1, // FIXME: Hardcoding only for testing
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
        console.log(`✅ Executed refund leaf ${refundLeaf.leafId} on ${chainName} (${chainId}): ${tx.hash}`);
        
        // Log individual refunds
        for (let i = 0; i < refundLeaf.refundAddresses.length; i++) {
          console.log(`  - Refunded ${ethers.formatEther(refundLeaf.refundAmounts[i])} to ${refundLeaf.refundAddresses[i]}`);
        }
        
      } catch (error) {
        console.error(`❌ Failed to execute refund leaf ${refundLeaf.leafId} on ${chainName}:`, error);
      }
    }
  }

  // Helper methods (unchanged from original)
  bytes32ToAddress(bytes32: any) {
    return ethers.getAddress('0x' + bytes32.slice(-40));
  }

  private createPoolRebalanceMerkleTree(leaves: any[]): MerkleTree {
    const leafHashes = leaves.map(leaf => this.hashPoolRebalanceLeaf(leaf));
    return new MerkleTree(leafHashes, ethers.keccak256, { sortPairs: true });
  }
  
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
    
    return ethers.keccak256(encoded);
  }
  
  private generatePoolRebalanceProofForLeaf(merkleTree: MerkleTree, leaf: any): string[] {
    const leafHash = this.hashPoolRebalanceLeaf(leaf);
    return merkleTree.getHexProof(leafHash);
  }

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
  
    return ethers.keccak256(encoded);
  }

  private createRelayerRefundMerkleTree(leaves: any[]): MerkleTree {
    const leafHashes = leaves.map(leaf => this.hashRelayerRefundLeaf(leaf));
    return new MerkleTree(leafHashes, ethers.keccak256, { sortPairs: true });
  }

  async stop() {
    this.isRunning = false;
    await this.redis.disconnect();
    console.log('🛑 Multi-chain DataWorker stopped');
  }
}

// Multi-chain configuration
const createMultiChainConfig = (): DataWorkerConfig => {
  const chains: ChainConfig[] = [];
  
  // Parse chains from environment variables
  const chainsConfigStr = process.env.CHAINS_CONFIG;
  if (chainsConfigStr) {
    try {
      const chainsData = JSON.parse(chainsConfigStr);
      for (const [chainId, chainData] of Object.entries(chainsData)) {
        chains.push({
          chainId: parseInt(chainId),
          type: (chainData as any).type || `chain-${chainId}`,
          rpc: (chainData as any).rpc,
          spokePoolAddress: (chainData as any).spokePoolAddress
        });
      }
    } catch (error) {
      console.error('Error parsing CHAINS_CONFIG:', error);
    }
  }
  
  return {
    hubPool: {
      rpc: process.env.HUBPOOL_RPC!,
      privateKey: process.env.HUBPOOL_PRIVATE_KEY!,
      address: process.env.HUBPOOL_ADDRESS!
    },
    chains,
    redisUrl: process.env.REDIS_URL!,
    pollingInterval: parseInt(process.env.POLLING_INTERVAL || '10000'),
    blockRange: parseInt(process.env.BLOCK_RANGE || '100'),
    minRefundVolume: process.env.MIN_REFUND_VOLUME || "0"
  };
};

const config = createMultiChainConfig();

console.log(`🚀 Starting Multi-chain DataWorker for ${config.chains.length} chains:`);
config.chains.forEach(chain => {
  console.log(`  - ${chain.type} (Chain ID: ${chain.chainId})`);
});

const dataWorker = new MultiChainAcrossDataWorker(config);

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