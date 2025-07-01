import { ethers } from 'ethers';
import Redis from 'redis';

interface RelayerConfig {
  chainA: { rpc: string; privateKey: string; spokePoolAddress: string; chainId: number };
  chainB: { rpc: string; privateKey: string; spokePoolAddress: string; chainId: number };
  redisUrl: string;
}

class AcrossRelayer {
  private providerA: ethers.JsonRpcProvider;
  private providerB: ethers.JsonRpcProvider;
  private walletA: ethers.Wallet;
  private walletB: ethers.Wallet;
  private spokePoolA: ethers.Contract;
  private spokePoolB: ethers.Contract;
  private redis: Redis.RedisClientType;

  constructor(config: RelayerConfig) {
    this.providerA = new ethers.JsonRpcProvider(config.chainA.rpc);
    this.providerB = new ethers.JsonRpcProvider(config.chainB.rpc);
    this.walletA = new ethers.Wallet(config.chainA.privateKey, this.providerA);
    this.walletB = new ethers.Wallet(config.chainB.privateKey, this.providerB);
    
    const spokePoolAbi = [
      "event FundsDeposited(bytes32 indexed inputToken, bytes32 indexed outputToken, uint256 inputAmount, uint256 outputAmount, uint256 indexed destinationChainId, uint256 indexed depositId, uint32 quoteTimestamp, uint32 fillDeadline, uint32 exclusivityDeadline, bytes32 indexed depositor, bytes32 recipient, bytes32 exclusiveRelayer, bytes message)",
      "function fillV3Relay((address,address,address,address,uint256,uint256,uint256,uint32,uint32,uint32,bytes), uint256) external"
    ];
    
    this.spokePoolA = new ethers.Contract(config.chainA.spokePoolAddress, spokePoolAbi, this.walletA);
    this.spokePoolB = new ethers.Contract(config.chainB.spokePoolAddress, spokePoolAbi, this.walletB);
    this.redis = Redis.createClient({ url: config.redisUrl });
  }

  async start() {
    await this.redis.connect();
    console.log('Relayer service started');
    
    this.spokePoolA.on('FundsDeposited', this.handleDeposit.bind(this, 'A'));
    this.spokePoolB.on('FundsDeposited', this.handleDeposit.bind(this, 'B'));
  }

  private async handleDeposit(sourceChain: string, ...args: any[]) {
    const [inputToken, outputToken, inputAmount, outputAmount, destinationChainId, depositId, quoteTimestamp, fillDeadline, exclusivityDeadline, depositor, recipient, exclusiveRelayer, message] = args;
    
    console.log(`Deposit detected on chain ${sourceChain}:`, { depositId: depositId.toString(), destinationChainId: destinationChainId.toString() });
    
    const targetSpokePool = destinationChainId.toString() === this.walletA.provider?.network?.chainId?.toString() ? this.spokePoolA : this.spokePoolB;
    
    try {
      const relayData = {
        depositor: ethers.getAddress(depositor.slice(26)),
        recipient: ethers.getAddress(recipient.slice(26)),
        exclusiveRelayer: ethers.getAddress(exclusiveRelayer.slice(26)),
        inputToken: ethers.getAddress(inputToken.slice(26)),
        outputToken: ethers.getAddress(outputToken.slice(26)),
        inputAmount,
        outputAmount,
        originChainId: sourceChain === 'A' ? this.walletA.provider?.network?.chainId : this.walletB.provider?.network?.chainId,
        depositId,
        fillDeadline,
        exclusivityDeadline,
        message
      };
      
      const tx = await targetSpokePool.fillV3Relay(relayData, 0);
      await tx.wait();
      
      console.log(`Relay fulfilled: ${tx.hash}`);
      await this.redis.publish('relay-fulfilled', JSON.stringify({ depositId: depositId.toString(), txHash: tx.hash }));
    } catch (error) {
      console.error('Error fulfilling relay:', error);
    }
  }
}

const config: RelayerConfig = {
  chainA: {
    rpc: process.env.CHAIN_A_RPC!,
    privateKey: process.env.CHAIN_A_PRIVATE_KEY!,
    spokePoolAddress: process.env.SPOKEPOOL_A_ADDRESS!,
    chainId: parseInt(process.env.CHAIN_A_ID!)
  },
  chainB: {
    rpc: process.env.CHAIN_B_RPC!,
    privateKey: process.env.CHAIN_B_PRIVATE_KEY!,
    spokePoolAddress: process.env.SPOKEPOOL_B_ADDRESS!,
    chainId: parseInt(process.env.CHAIN_B_ID!)
  },
  redisUrl: process.env.REDIS_URL!
};

const relayer = new AcrossRelayer(config);
relayer.start().catch(console.error);
