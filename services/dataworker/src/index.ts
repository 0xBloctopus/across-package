import { ethers } from 'ethers';
import { createClient, RedisClientType} from 'redis';
import { MerkleTree } from 'merkletreejs';
import 'dotenv/config'; 

interface DataWorkerConfig {
  hubPool: { rpc: string; privateKey: string; address: string };
  chainA: { rpc: string; spokePoolAddress: string; chainId: number };
  chainB: { rpc: string; spokePoolAddress: string; chainId: number };
  redisUrl: string;
  pollingInterval?: number; // Add polling interval config
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
            timestamp: Date.now()
          };
        
          this.relayData.push(relayEntry);
        
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
    
    const leaves = this.relayData.map(relay => 
      ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes32', 'bytes32', 'uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'bytes32'],
        [relay.inputToken, relay.outputToken, relay.inputAmount, relay.outputAmount, relay.repaymentChainId, relay.originChainId, relay.depositId, relay.relayer]
      ))
    );
    console.log("Leaves", leaves);
    
    const merkleTree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
    console.log("merkletree", merkleTree);
    const root = merkleTree.getHexRoot();
    
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
        root,
        ethers.ZeroHash
      );
      
      await tx.wait();
      console.log(`Merkle root submitted to HubPool: ${tx.hash}`);
      
      this.relayData = [];
    } catch (error) {
      console.error('Error submitting Merkle root:', error);
    }
  }

  async stop() {
    this.isRunning = false;
    await this.redis.disconnect();
    console.log('stopped');
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
