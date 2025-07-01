import { ethers } from 'ethers';
import Redis from 'redis';
import { MerkleTree } from 'merkletreejs';

interface DataWorkerConfig {
  hubPool: { rpc: string; privateKey: string; address: string };
  chainA: { rpc: string; spokePoolAddress: string; chainId: number };
  chainB: { rpc: string; spokePoolAddress: string; chainId: number };
  redisUrl: string;
}

class AcrossDataWorker {
  private hubPoolProvider: ethers.JsonRpcProvider;
  private hubPoolWallet: ethers.Wallet;
  private hubPool: ethers.Contract;
  private providerA: ethers.JsonRpcProvider;
  private providerB: ethers.JsonRpcProvider;
  private spokePoolA: ethers.Contract;
  private spokePoolB: ethers.Contract;
  private redis: Redis.RedisClientType;
  private relayData: any[] = [];

  constructor(config: DataWorkerConfig) {
    this.hubPoolProvider = new ethers.JsonRpcProvider(config.hubPool.rpc);
    this.hubPoolWallet = new ethers.Wallet(config.hubPool.privateKey, this.hubPoolProvider);
    
    const hubPoolAbi = [
      "function proposeRootBundle(uint256[] memory bundleEvaluationBlockNumbers, uint8 poolRebalanceLeafCount, bytes32 poolRebalanceRoot, bytes32 relayerRefundRoot, bytes32 slowRelayRoot) external"
    ];
    this.hubPool = new ethers.Contract(config.hubPool.address, hubPoolAbi, this.hubPoolWallet);
    
    this.providerA = new ethers.JsonRpcProvider(config.chainA.rpc);
    this.providerB = new ethers.JsonRpcProvider(config.chainB.rpc);
    
    const spokePoolAbi = [
      "event FilledRelay(bytes32 indexed inputToken, bytes32 indexed outputToken, uint256 inputAmount, uint256 outputAmount, uint256 repaymentChainId, uint256 indexed originChainId, uint256 indexed depositId, uint32 fillDeadline, uint32 exclusivityDeadline, bytes32 exclusiveRelayer, bytes32 indexed relayer, bytes32 depositor, bytes32 recipient, bytes32 messageHash, tuple(bytes32,bytes32,uint256,uint8) relayExecutionInfo)"
    ];
    
    this.spokePoolA = new ethers.Contract(config.chainA.spokePoolAddress, spokePoolAbi, this.providerA);
    this.spokePoolB = new ethers.Contract(config.chainB.spokePoolAddress, spokePoolAbi, this.providerB);
    this.redis = Redis.createClient({ url: config.redisUrl });
  }

  async start() {
    await this.redis.connect();
    console.log('DataWorker service started');
    
    this.spokePoolA.on('FilledRelay', this.handleFilledRelay.bind(this, 'A'));
    this.spokePoolB.on('FilledRelay', this.handleFilledRelay.bind(this, 'B'));
    
    await this.redis.subscribe('relay-fulfilled', this.processRelayData.bind(this));
  }

  private async handleFilledRelay(chain: string, ...args: any[]) {
    const [inputToken, outputToken, inputAmount, outputAmount, repaymentChainId, originChainId, depositId, fillDeadline, exclusivityDeadline, exclusiveRelayer, relayer, depositor, recipient, messageHash, relayExecutionInfo] = args;
    
    console.log(`FilledRelay event detected on chain ${chain}:`, { depositId: depositId.toString() });
    
    this.relayData.push({
      chain,
      inputToken,
      outputToken,
      inputAmount,
      outputAmount,
      repaymentChainId,
      originChainId,
      depositId,
      relayer,
      timestamp: Date.now()
    });
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
    
    const merkleTree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });
    const root = merkleTree.getHexRoot();
    
    try {
      const currentBlock = await this.hubPoolProvider.getBlockNumber();
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
  redisUrl: process.env.REDIS_URL!
};

const dataWorker = new AcrossDataWorker(config);
dataWorker.start().catch(console.error);
