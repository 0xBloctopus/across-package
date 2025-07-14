import { ethers } from 'ethers';
import { createClient, RedisClientType} from 'redis';
import { MerkleTree } from 'merkletreejs';
import 'dotenv/config';

interface RelayerRefundLeaf {
  amountToReturn: string;
  chainId: number;
  refundAmounts: string[];
  leafId: number;
  l2TokenAddress: string;
  refundAddresses: string[];
}

interface RelayerRefundData {
  relayer: string;
  inputToken: string;
  outputToken: string;
  inputAmount: string;
  outputAmount: string;
  originChainId: number;
  destinationChainId: number;
  depositId: string;
  realizedLpFeePct: string;
  fillBlock: number;
}

interface BalanceAllocator {
  getUsed(chainId: number, token: string, account: string): string;
  setUsed(chainId: number, token: string, account: string, amount: string): void;
  addUsed(chainId: number, token: string, account: string, amount: string): void;
}

class SimpleBalanceAllocator implements BalanceAllocator {
  private balances = new Map<string, string>();
  
  private getKey(chainId: number, token: string, account: string): string {
    return `${chainId}-${token}-${account}`;
  }
  
  getUsed(chainId: number, token: string, account: string): string {
    return this.balances.get(this.getKey(chainId, token, account)) || "0";
  }
  
  setUsed(chainId: number, token: string, account: string, amount: string): void {
    this.balances.set(this.getKey(chainId, token, account), amount);
  }
  
  addUsed(chainId: number, token: string, account: string, amount: string): void {
    const current = BigInt(this.getUsed(chainId, token, account));
    const additional = BigInt(amount);
    this.setUsed(chainId, token, account, (current + additional).toString());
  }
}

interface DataWorkerConfig {
  hubPool: { rpc: string; privateKey: string; address: string };
  chainA: { rpc: string; spokePoolAddress: string; chainId: number };
  chainB: { rpc: string; spokePoolAddress: string; chainId: number };
  redisUrl: string;
  pollingInterval?: number;
  blockRange?: number;
}

class AcrossDataWorker {
  private hubPoolProvider: ethers.JsonRpcProvider;
  private hubPoolWallet: ethers.Wallet;
  private hubPool: ethers.Contract;
  private providerA: ethers.JsonRpcProvider;
  private providerB: ethers.JsonRpcProvider;
  private spokePoolA: ethers.Contract;
  private spokePoolB: ethers.Contract;
  private redis: RedisClientType;
  private relayData: any[] = [];
  private relayerRefundData: RelayerRefundData[] = [];
  private pollingInterval: number;
  private lastProcessedBlockA: number = 0;
  private lastProcessedBlockB: number = 0;
  private isRunning: boolean = false;
  private blockRange: number;

  constructor(config: DataWorkerConfig) {
    this.hubPoolProvider = new ethers.JsonRpcProvider(config.hubPool.rpc);
    this.hubPoolWallet = new ethers.Wallet(config.hubPool.privateKey, this.hubPoolProvider);
    
    const hubPoolAbi = [
      // "function proposeRootBundle(uint256[] memory bundleEvaluationBlockNumbers, uint8 poolRebalanceLeafCount, bytes32 poolRebalanceRoot, bytes32 relayerRefundRoot, bytes32 slowRelayRoot) external"
      "function proposeRootBundle(uint256[] calldata bundleEvaluationBlockNumbers, uint8 poolRebalanceLeafCount, bytes32 poolRebalanceRoot, bytes32 relayerRefundRoot, bytes32 slowRelayRoot)"
    ];
    this.hubPool = new ethers.Contract(config.hubPool.address, hubPoolAbi, this.hubPoolWallet);
    
    this.providerA = new ethers.JsonRpcProvider(config.chainA.rpc);
    this.providerB = new ethers.JsonRpcProvider(config.chainB.rpc);

    const spokePoolAbi = [
      "event FilledRelay(bytes32 indexed inputToken, bytes32 indexed outputToken, uint256 inputAmount, uint256 outputAmount, uint256 repaymentChainId, uint256 indexed originChainId, uint256 indexed depositId, uint32 fillDeadline, uint32 exclusivityDeadline, bytes32 exclusiveRelayer, bytes32 indexed relayer, bytes32 depositor, bytes32 recipient, bytes32 messageHash, tuple(bytes32 updatedRecipient, bytes32 updatedMessageHash,uint256 updatedOutputAmount, uint8 fillType) relayExecutionInfo)"
    ];
    
    this.spokePoolA = new ethers.Contract(config.chainA.spokePoolAddress, spokePoolAbi, this.providerA);
    this.spokePoolB = new ethers.Contract(config.chainB.spokePoolAddress, spokePoolAbi, this.providerB);
    this.redis = createClient({ url: config.redisUrl });
    this.pollingInterval = config.pollingInterval || 15000; // Default 15 seconds
    this.blockRange = 100;
  }

  async start() {
    await this.redis.connect();
    console.log('DataWorker service started');
    
    // Initialize last processed blocks
    this.lastProcessedBlockA = await this.providerA.getBlockNumber()-100; // Start from 100 blocks ago
    this.lastProcessedBlockB = await this.providerB.getBlockNumber()-100;
    
    this.isRunning = true;
    
    // Start polling for events instead of using event listeners
    this.startPolling();
    
    // await this.redis.subscribe('relay-fulfilled', this.processRelayData.bind(this));
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
        'tuple(bytes32 updatedRecipient, bytes32 updatedMessageHash, uint256 updatedOutputAmount, uint8 fillType)'  // relayExecutionInfo
      ];
      const filter = {
        address: spokePool,
        fromBlock,
        toBlock,
        topics: [eventTopic]
      };

      const logs = await provider.getLogs(filter);
      const abiCoder = ethers.AbiCoder.defaultAbiCoder();
    
      for (const log of logs) {
        try {
          const decoded = abiCoder.decode(nonIndexedTypes, log.data);
          console.log('decoded', decoded)
    
          const result = {
            indexed: {
              originChainId: BigInt(log.topics[1]),
              depositId: BigInt(log.topics[2]),
              relayer: log.topics[3]
            },
            data: {
              inputToken: decoded[0].toString(),
              outputToken: decoded[1].toString(),
              inputAmount: decoded[2].toString(),
              outputAmount: decoded[3].toString(),
              repaymentChainId: decoded[4].toString(),
              fillDeadline: decoded[5],
              exclusivityDeadline: decoded[6],
              exclusiveRelayer: decoded[7],
              depositor: decoded[8],
              recipient: decoded[9],
              messageHash: decoded[10],
              relayExecutionInfo: {
                updatedRecipient: decoded[11][0],
                updatedMessageHash: decoded[11][1],
                updatedOutputAmount: decoded[11][2].toString(),
                fillType: decoded[11][3]
              }
            }
          };
          
          console.log('✅ FilledRelay log decoded:', result);

          const relayEntry = {
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
            blockNumber: log.blockNumber
          };
        
          this.relayData.push(relayEntry);
          
          const refundData: RelayerRefundData = {
            relayer: log.topics[3],
            inputToken: decoded[0].toString(),
            outputToken: decoded[1].toString(),
            inputAmount: decoded[2].toString(),
            outputAmount: decoded[3].toString(),
            originChainId: parseInt(BigInt(log.topics[1]).toString()),
            destinationChainId: chainLabel === 'A' ? parseInt(process.env.CHAIN_A_ID!) : parseInt(process.env.CHAIN_B_ID!),
            depositId: BigInt(log.topics[2]).toString(),
            realizedLpFeePct: this.calculateRealizedLpFee(decoded[2].toString(), decoded[3].toString()),
            fillBlock: log.blockNumber
          };
          
          this.relayerRefundData.push(refundData);
        
          // Optionally trigger Merkle tree build
          // if (this.relayData.length >= 10) {
            await this.processRelayData();
          // }
        } catch (err) {
          console.warn('❌ Failed to decode log:', err);
        }
      } 

      
      // console.log(`📝 Found ${events.length} FilledRelay events on chain ${chainLabel}`);
      // console.log('Event: ', events)
      // // console.log('Spokepool: ', spokePool)

      // for (const event of events) {
      //   if ('args' in event) { 
      //     const [inputToken, outputToken, inputAmount, outputAmount, repaymentChainId, originChainId, depositId, fillDeadline, exclusivityDeadline, exclusiveRelayer, relayer, depositor, recipient, messageHash, relayExecutionInfo] = event.args;
      //     console.log('FilledRelay event detected');
      //     // await this.handleDepositEvent(chainLabel, event);
      //   }
      // }

      // Update last processed block
      if (chainLabel === 'A') {
        this.lastProcessedBlockA = toBlock;
      } else {
        this.lastProcessedBlockB = toBlock;
      }

      await this.redis.set(`lastProcessedBlock_${chainLabel}`, toBlock.toString());
      console.log(`Redis updated: lastProcessedBlock_${chainLabel} = ${toBlock}`);

    } catch (error) {
      console.error(`❌ Error querying events for chain ${chainLabel}:`, error);
    }
  }


  private async processRelayData() {
    if (this.relayData.length === 0) return;
    
    console.log('Processing relay data for Merkle tree construction...');
    
    const relayerRefundLeaves = this.buildRelayerRefundLeaves();
    console.log("Relayer refund leaves:", relayerRefundLeaves);
    this.logRefundSummary(relayerRefundLeaves);
    
    const relayerRefundTree = new MerkleTree(
      relayerRefundLeaves.map(leaf => 
        ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
          ['uint256', 'uint256', 'uint256[]', 'uint32', 'address', 'address[]'],
          [leaf.amountToReturn, leaf.chainId, leaf.refundAmounts, leaf.leafId, leaf.l2TokenAddress, leaf.refundAddresses]
        ))
      ),
      ethers.keccak256,
      { sortPairs: true }
    );
    
    const relayerRefundRoot = relayerRefundTree.getHexRoot();
    console.log("Relayer refund root:", relayerRefundRoot);
    
    try {
      const currentBlock = await this.hubPoolProvider.getBlockNumber();
      console.log("current block", currentBlock);
      console.log("hubpool provider", this.hubPool.target);
      const network = await this.hubPoolProvider.getNetwork();
      console.log("Connected to:", network.name, network.chainId);
      
      const tx = await this.hubPool.proposeRootBundle(
        [currentBlock],
        1,
        ethers.ZeroHash,
        relayerRefundRoot,
        ethers.ZeroHash
      );
      
      await tx.wait();
      console.log(`Merkle root submitted to HubPool: ${tx.hash}`);
      console.log(`Relayer refund leaves count: ${relayerRefundLeaves.length}`);
      
      console.log('Simulating complete refund execution flow...');
      
      const balanceAllocator = new SimpleBalanceAllocator();
      
      await this.executePoolRebalanceLeaves({}, balanceAllocator);
      
      console.log('Simulating root bundle relay to spoke pools...');
      
      await this.executeRelayerRefundLeaves({}, balanceAllocator);
      
      this.relayData = [];
      this.relayerRefundData = [];
    } catch (error) {
      console.error('Error submitting Merkle root:', error);
    }
  }

  async stop() {
    this.isRunning = false;
    await this.redis.disconnect();
    console.log('DataWorker stopped');
  }

  private buildRelayerRefundLeaves(): RelayerRefundLeaf[] {
    const refundLeaves: RelayerRefundLeaf[] = [];
    
    const refundsByChainAndToken = new Map<string, Map<string, RelayerRefundData[]>>();
    
    for (const refund of this.relayerRefundData) {
      const chainKey = refund.destinationChainId.toString();
      const tokenKey = refund.outputToken;
      
      if (!refundsByChainAndToken.has(chainKey)) {
        refundsByChainAndToken.set(chainKey, new Map());
      }
      
      const tokenMap = refundsByChainAndToken.get(chainKey)!;
      if (!tokenMap.has(tokenKey)) {
        tokenMap.set(tokenKey, []);
      }
      
      tokenMap.get(tokenKey)!.push(refund);
    }
    
    let leafId = 0;
    
    for (const [chainId, tokenMap] of refundsByChainAndToken) {
      for (const [l2TokenAddress, refunds] of tokenMap) {
        const relayerRefunds = new Map<string, string>();
        
        for (const refund of refunds) {
          const currentAmount = relayerRefunds.get(refund.relayer) || "0";
          const newAmount = (BigInt(currentAmount) + BigInt(refund.outputAmount)).toString();
          relayerRefunds.set(refund.relayer, newAmount);
        }
        
        const refundAddresses = Array.from(relayerRefunds.keys());
        const refundAmounts = Array.from(relayerRefunds.values());
        
        const leaf: RelayerRefundLeaf = {
          amountToReturn: "0",
          chainId: parseInt(chainId),
          refundAmounts,
          leafId: leafId++,
          l2TokenAddress,
          refundAddresses
        };
        
        if (this.validateRefundLeaf(leaf)) {
          refundLeaves.push(leaf);
        }
      }
    }
    
    return refundLeaves;
  }

  private calculateRealizedLpFee(inputAmount: string, outputAmount: string): string {
    const input = BigInt(inputAmount);
    const output = BigInt(outputAmount);
    return (input - output).toString();
  }
  
  private validateRefundLeaf(leaf: RelayerRefundLeaf): boolean {
    if (leaf.refundAddresses.length !== leaf.refundAmounts.length) {
      console.error("Refund addresses and amounts length mismatch", leaf);
      return false;
    }
    
    for (const address of leaf.refundAddresses) {
      try {
        ethers.getAddress(address);
      } catch (error) {
        console.error("Invalid refund address", address, error);
        return false;
      }
    }
    
    return true;
  }
  
  private logRefundSummary(leaves: RelayerRefundLeaf[]): void {
    console.log("=== Relayer Refund Summary ===");
    for (const leaf of leaves) {
      console.log(`Chain ${leaf.chainId}, Token ${leaf.l2TokenAddress}:`);
      for (let i = 0; i < leaf.refundAddresses.length; i++) {
        console.log(`  ${leaf.refundAddresses[i]}: ${leaf.refundAmounts[i]}`);
      }
    }
    console.log("==============================");
  }

  async executePoolRebalanceLeaves(spokePoolClients: any, balanceAllocator: BalanceAllocator) {
    console.log('Executing pool rebalance leaves...');
    
    console.log('Pool rebalance leaves executed successfully');
    
    try {
      await this.redis.publish('pool_rebalance_executed', JSON.stringify({
        timestamp: Date.now(),
        message: 'Pool rebalance leaves executed'
      }));
    } catch (error) {
      console.error('Error publishing pool rebalance event:', error);
    }
  }

  async executeRelayerRefundLeaves(spokePoolClients: any, balanceAllocator: BalanceAllocator) {
    console.log('Executing relayer refund leaves...');
    
    const relayerRefundLeaves = this.buildRelayerRefundLeaves();
    
    if (relayerRefundLeaves.length === 0) {
      console.log('No relayer refund leaves to execute');
      return;
    }
    
    console.log(`Executing ${relayerRefundLeaves.length} relayer refund leaves`);
    
    for (const leaf of relayerRefundLeaves) {
      try {
        await this._executeRelayerRefundLeaves(leaf, balanceAllocator);
        console.log(`Executed refund leaf ${leaf.leafId} for chain ${leaf.chainId}`);
      } catch (error) {
        console.error(`Error executing refund leaf ${leaf.leafId}:`, error);
      }
    }
    
    try {
      await this.redis.publish('relayer_refunds_executed', JSON.stringify({
        timestamp: Date.now(),
        leavesCount: relayerRefundLeaves.length,
        message: 'Relayer refund leaves executed'
      }));
    } catch (error) {
      console.error('Error publishing refund execution event:', error);
    }
    
    console.log('Relayer refund leaves execution completed');
  }

  private async _executeRelayerRefundLeaves(leaf: RelayerRefundLeaf, balanceAllocator: BalanceAllocator) {
    console.log(`Executing refund leaf ${leaf.leafId} for chain ${leaf.chainId}`);
    
    for (let i = 0; i < leaf.refundAddresses.length; i++) {
      const refundAddress = leaf.refundAddresses[i];
      const refundAmount = leaf.refundAmounts[i];
      
      balanceAllocator.addUsed(leaf.chainId, leaf.l2TokenAddress, refundAddress, refundAmount);
      
      console.log(`Refunded ${refundAmount} tokens to ${refundAddress} on chain ${leaf.chainId}`);
    }
    
    if (leaf.amountToReturn !== "0") {
      console.log(`Returning ${leaf.amountToReturn} tokens to HubPool for chain ${leaf.chainId}`);
      
      balanceAllocator.addUsed(
        leaf.chainId, 
        leaf.l2TokenAddress, 
        this.hubPool.target as string, 
        `-${leaf.amountToReturn}`
      );
    }
    
    console.log(`Successfully processed refund leaf ${leaf.leafId}`);
  }

  createBalanceAllocator(): BalanceAllocator {
    return new SimpleBalanceAllocator();
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
  pollingInterval: 10000 // Poll every 10 seconds
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
