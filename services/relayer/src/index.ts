import { ethers } from 'ethers';
import { createClient, RedisClientType} from 'redis';
import 'dotenv/config';

interface ChainConfig {
  rpc: string;
  privateKey: string;
  spokePoolAddress: string;
  chainId: number;
  type: string; 
}

interface RelayerConfig {
  chains: { [chainId: string]: ChainConfig };
  redisUrl: string;
  pollingInterval?: number;
  blockRange?: number;
  repaymentChainId?: number;
  repaymentAddress?: string;
}

interface ChainState {
  provider: ethers.JsonRpcProvider;
  wallet: ethers.Wallet;
  spokePool: ethers.Contract;
  lastProcessedBlock: number;
  chainId: string;
  config: ChainConfig;
}

class MultiChainAcrossRelayer {
  private chains: Map<string, ChainState> = new Map();
  private redis: RedisClientType;
  private pollingInterval: number;
  private blockRange: number;
  private isRunning: boolean = false;
  private repaymentChainId: number;
  private repaymentAddress: string;

  constructor(config: RelayerConfig) {
    console.log('🚀 Initializing Multi-Chain Across Relayer...');
    
    this.pollingInterval = config.pollingInterval || 5000;
    this.blockRange = config.blockRange || 100;
    this.repaymentChainId = config.repaymentChainId || 1225280;
    this.repaymentAddress = config.repaymentAddress || '0x333F13a6913553EE8C380173B16449d1F7AD0aF9';
    this.redis = createClient({ url: config.redisUrl });

    const spokePoolAbi = [
      "event FundsDeposited(bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, uint256 indexed destinationChainId, uint256 indexed depositId, uint32 quoteTimestamp, uint32 fillDeadline, uint32 exclusivityDeadline, bytes32 indexed depositor, bytes32 recipient, bytes32 exclusiveRelayer, bytes message)",
      "function fillRelay((bytes32,bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,uint256,uint32,uint32,bytes),uint256,bytes32) external"
    ];

    // Initialize all chains
    for (const [chainId, chainConfig] of Object.entries(config.chains)) {
      console.log(`🔧 Setting up chain ${chainConfig.type} (${chainId})`);
      
      const provider = new ethers.JsonRpcProvider(chainConfig.rpc);
      const wallet = new ethers.Wallet(chainConfig.privateKey, provider);
      const spokePool = new ethers.Contract(chainConfig.spokePoolAddress, spokePoolAbi, wallet);

      const chainState: ChainState = {
        provider,
        wallet,
        spokePool,
        lastProcessedBlock: 0,
        chainId,
        config: chainConfig
      };

      this.chains.set(chainId, chainState);
      console.log(`✅ Chain ${chainConfig.type} (${chainId}) initialized`);
    }

    console.log(`📊 Total chains configured: ${this.chains.size}`);
  }

  async start() {
    await this.redis.connect();
    console.log('✅ Redis connected');
    
    // Initialize all chains
    for (const [chainId, chainState] of this.chains) {
      try {
        const network = await chainState.provider.getNetwork();
        console.log(`🔗 Chain ${chainState.config.type}: (${network.chainId})`);
        
        // Get current block number
        chainState.lastProcessedBlock = await chainState.provider.getBlockNumber();
        console.log(`📊 Starting from block for ${chainState.config.type}: ${chainState.lastProcessedBlock}`);
        
        // Verify chain ID matches configuration
        if (network.chainId.toString() !== chainId) {
          console.warn(`⚠️  Warning: Chain ID mismatch for ${chainState.config.type}. Expected: ${chainId}, Got: ${network.chainId}`);
        }
      } catch (error) {
        console.error(`❌ Error initializing chain ${chainState.config.type}:`, error);
        throw error;
      }
    }
    
    await this.initializeFromRedis();
    
    this.isRunning = true;
    console.log('🚀 Multi-chain relayer service started');
    
    // Start polling all chains
    this.startPolling();
  }

  async stop() {
    this.isRunning = false;
    await this.redis.disconnect();
    console.log('🛑 Multi-chain relayer service stopped');
  }

  private async startPolling() {
    // Create a polling function for each chain
    const pollingFunctions = Array.from(this.chains.entries()).map(([chainId, chainState]) => {
      const pollChain = async () => {
        if (!this.isRunning) return;
        
        try {
          await this.pollForEvents(chainId, chainState);
        } catch (error) {
          console.error(`❌ Error polling chain ${chainState.config.type} (${chainId}):`, error);
        }
        
        if (this.isRunning) {
          setTimeout(pollChain, this.pollingInterval);
        }
      };

      return pollChain;
    });

    // Start all polling functions
    pollingFunctions.forEach(pollFn => pollFn());
    console.log(`🔄 Started polling ${pollingFunctions.length} chains`);
  }

  private async pollForEvents(chainId: string, chainState: ChainState) {
    const currentBlock = await chainState.provider.getBlockNumber();
    
    if (currentBlock <= chainState.lastProcessedBlock) {
      return;
    }

    const fromBlock = chainState.lastProcessedBlock + 1;
    const toBlock = Math.min(fromBlock + this.blockRange - 1, currentBlock);

    console.log(`🔍 Polling ${chainState.config.type} (${chainId}) from block ${fromBlock} to ${toBlock}`);

    try {
      // Query FundsDeposited events
      const events = await chainState.spokePool.queryFilter(
        chainState.spokePool.filters.FundsDeposited(),
        fromBlock,
        toBlock
      );

      console.log(`📝 Found ${events.length} FundsDeposited events on ${chainState.config.type}`);

      for (const event of events) {
        if ('args' in event) { 
          await this.handleDepositEvent(chainId, chainState, event);
        }
      }

      // Update last processed block
      chainState.lastProcessedBlock = toBlock;
      await this.redis.set(`lastProcessedBlock_${chainId}`, toBlock.toString());

    } catch (error) {
      console.error(`❌ Error querying events for ${chainState.config.type} (${chainId}):`, error);
    }
  }

  private async handleDepositEvent(sourceChainId: string, sourceChainState: ChainState, event: ethers.EventLog) {
    const { args } = event;
    if (!args) return;

    const [inputToken, outputToken, inputAmount, outputAmount, destinationChainId, depositId, quoteTimestamp, fillDeadline, exclusivityDeadline, depositor, recipient, exclusiveRelayer, message] = args;
    const inputTokenAddress = ethers.getAddress('0x' + inputToken.slice(26)); 
    const outputTokenAddress = ethers.getAddress('0x' + outputToken.slice(26));
    const toBytes32 = (address: string) => ethers.zeroPadValue(address, 32);

    console.log(`🎯 Deposit detected on ${sourceChainState.config.type}:`, { 
      depositId: depositId.toString(), 
      destinationChainId: destinationChainId.toString(),
      blockNumber: event.blockNumber,
      transactionHash: event.transactionHash,
      inputTokenAddress,
      outputTokenAddress,
      inputAmount: inputAmount.toString(),
      outputAmount: outputAmount.toString(),
      depositor: toBytes32(depositor),
      recipient: toBytes32(recipient), 
    });
    
    // Find target chain
    const targetChainId = destinationChainId.toString();
    const targetChainState = this.chains.get(targetChainId);
    
    if (!targetChainState) {
      console.log(`⚠️  Destination chain ${targetChainId} not supported by this relayer`);
      console.log(`📋 Supported chains: ${Array.from(this.chains.keys()).join(', ')}`);
      return;
    }

    console.log(`🎯 Filling relay on ${targetChainState.config.type} (${targetChainId})`);
    
    try {
      // Check if already processed
      const processedKey = `processed_${depositId.toString()}_${event.transactionHash}`;
      const alreadyProcessed = await this.redis.get(processedKey);
      
      if (alreadyProcessed) {
        console.log(`⏭️  Deposit ${depositId.toString()} already processed, skipping`);
        return;
      }

      const relayData = [
        toBytes32(depositor),
        toBytes32(recipient),
        toBytes32(exclusiveRelayer),
        toBytes32(inputToken),
        toBytes32(outputToken),
        inputAmount,
        outputAmount,
        sourceChainId,
        depositId,
        fillDeadline,
        exclusivityDeadline,
        message
      ];
      
      console.log(`📝 Relay data prepared for ${targetChainState.config.type}`);
      const repaymentAddress = toBytes32(this.repaymentAddress);

      const tx = await targetChainState.spokePool.fillRelay(relayData, this.repaymentChainId, repaymentAddress);
      console.log(`📤 Fill transaction sent on ${targetChainState.config.type}: ${tx.hash}`);
      
      const receipt = await tx.wait();
      console.log(`✅ Relay fulfilled: ${tx.hash} (Block: ${receipt.blockNumber}) on ${targetChainState.config.type}`);
      
      // Mark as processed
      await this.redis.set(processedKey, 'true', { EX: 86400 });
      
      // Publish completion
      await this.redis.publish('relay-fulfilled', JSON.stringify({ 
        depositId: depositId.toString(), 
        txHash: tx.hash,
        sourceChain: sourceChainState.config.type,
        sourceChainId: sourceChainId,
        targetChain: targetChainState.config.type,
        targetChainId: targetChainId,
        sourceTransactionHash: event.transactionHash,
        blockNumber: receipt.blockNumber
      }));
      
    } catch (error) {
      console.error(`❌ Error fulfilling relay on ${targetChainState.config.type}:`, error);
    
      if (typeof error === 'object' && error !== null) {
        if ('code' in error && (error as any).code === 'CALL_EXCEPTION') {
          console.error('Call exception details:', (error as any).reason);
        }
        if ('transaction' in error) {
          console.error('Failed transaction data:', (error as any).transaction);
        }
      }
    }
  }

  async initializeFromRedis() {
    try {
      for (const [chainId, chainState] of this.chains) {
        const lastBlockKey = `lastProcessedBlock_${chainId}`;
        const lastBlock = await this.redis.get(lastBlockKey);
        
        if (lastBlock) {
          chainState.lastProcessedBlock = parseInt(lastBlock);
          console.log(`📊 Recovered ${chainState.config.type} from block: ${chainState.lastProcessedBlock}`);
        }
      }
    } catch (error) {
      console.error('❌ Error recovering from Redis:', error);
    }
  }

  // Utility methods for runtime chain management
  async addChain(chainId: string, chainConfig: ChainConfig) {
    if (this.chains.has(chainId)) {
      throw new Error(`Chain ${chainId} already exists`);
    }

    console.log(`🔧 Adding new chain ${chainConfig.type} (${chainId})`);
    
    const spokePoolAbi = [
      "event FundsDeposited(bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, uint256 indexed destinationChainId, uint256 indexed depositId, uint32 quoteTimestamp, uint32 fillDeadline, uint32 exclusivityDeadline, bytes32 indexed depositor, bytes32 recipient, bytes32 exclusiveRelayer, bytes message)",
      "function fillRelay((bytes32,bytes32,bytes32,bytes32,bytes32,uint256,uint256,uint256,uint256,uint32,uint32,bytes),uint256,bytes32) external"
    ];

    const provider = new ethers.JsonRpcProvider(chainConfig.rpc);
    const wallet = new ethers.Wallet(chainConfig.privateKey, provider);
    const spokePool = new ethers.Contract(chainConfig.spokePoolAddress, spokePoolAbi, wallet);

    const chainState: ChainState = {
      provider,
      wallet,
      spokePool,
      lastProcessedBlock: await provider.getBlockNumber(),
      chainId,
      config: chainConfig
    };

    this.chains.set(chainId, chainState);
    console.log(`✅ Chain ${chainConfig.type} (${chainId}) added successfully`);
  }

  removeChain(chainId: string) {
    if (!this.chains.has(chainId)) {
      throw new Error(`Chain ${chainId} does not exist`);
    }

    const chainState = this.chains.get(chainId)!;
    this.chains.delete(chainId);
    console.log(`🗑️  Chain ${chainState.config.type} (${chainId}) removed`);
  }

  getChainStatus() {
    const status = Array.from(this.chains.entries()).map(([chainId, chainState]) => ({
      chainId,
      name: chainState.config.type,
      lastProcessedBlock: chainState.lastProcessedBlock,
      spokePoolAddress: chainState.config.spokePoolAddress
    }));

    return {
      totalChains: this.chains.size,
      isRunning: this.isRunning,
      chains: status
    };
  }
}

// Function to build chain configuration from environment variables
function buildChainsConfig(): { [chainId: string]: ChainConfig } {
  const chains: { [chainId: string]: ChainConfig } = {};
  
  if (process.env.CHAINS_CONFIG) {
    try {
      const chainsFromEnv = JSON.parse(process.env.CHAINS_CONFIG);
      
      // Replace environment variable placeholders with actual values
      for (const [chainId, chainConfig] of Object.entries(chainsFromEnv as any)) {
        const config = chainConfig as any;
        chains[chainId] = {
          rpc: process.env[config.rpc.replace('${', '').replace('}', '')] || config.rpc,
          privateKey: process.env[config.privateKey.replace('${', '').replace('}', '')] || config.privateKey,
          spokePoolAddress: process.env[config.spokePoolAddress.replace('${', '').replace('}', '')] || config.spokePoolAddress,
          chainId: config.chainId,
          type: config.type
        };
      }
      
      console.log(`🔧 Loaded ${Object.keys(chains).length} chains from CHAINS_CONFIG`);
      return chains;
    } catch (error) {
      console.error('❌ Error parsing CHAINS_CONFIG:', error);
      throw error;
    }
  }

  
  if (Object.keys(chains).length === 0) {
    throw new Error('No chains configured. Please set up chain configuration in environment variables.');
  }
  
  return chains;
}

// Build configuration from environment
const config: RelayerConfig = {
  chains: buildChainsConfig(),
  redisUrl: process.env.REDIS_URL!,
  pollingInterval: parseInt(process.env.POLLING_INTERVAL || '5000'),
  blockRange: parseInt(process.env.BLOCK_RANGE || '100'),
  repaymentChainId: parseInt(process.env.REPAYMENT_CHAIN_ID || '1225280'),
  repaymentAddress: process.env.REPAYMENT_ADDRESS || '0x333F13a6913553EE8C380173B16449d1F7AD0aF9'
};

const relayer = new MultiChainAcrossRelayer(config);

// Add some status logging
setInterval(() => {
  if (relayer.getChainStatus().isRunning) {
    const status = relayer.getChainStatus();
    console.log(`📊 Relayer Status: ${status.totalChains} chains active`);
  }
}, 60000); // Log every minute

process.on('SIGINT', async () => {
  console.log('🛑 Received SIGINT, shutting down gracefully...');
  await relayer.stop();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('🛑 Received SIGTERM, shutting down gracefully...');
  await relayer.stop();
  process.exit(0);
});

relayer.start().catch(console.error);