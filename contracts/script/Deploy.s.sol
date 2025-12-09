// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/IndexFund.sol";
import "../src/FundFactory.sol";
import "../src/FundGovernance.sol";
import "../src/interfaces/IIndexFund.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    address constant SWAP_ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    uint256 constant MANAGEMENT_FEE = 200;
    uint256 constant VOTING_PERIOD = 3 days;
    uint256 constant QUORUM_PERCENTAGE = 1000;
    uint256 constant PROPOSAL_THRESHOLD = 100 * 10 ** 18;

    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;

        IndexFund fundImplementation = new IndexFund();
        FundFactory factoryImplementation = new FundFactory();
        FundGovernance governanceImplementation = new FundGovernance();

        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImplementation),
            abi.encodeWithSelector(FundFactory.initialize.selector, address(fundImplementation), SWAP_ROUTER, deployer)
        );
        FundFactory factory = FundFactory(address(factoryProxy));

        ERC1967Proxy govProxy = new ERC1967Proxy(
            address(governanceImplementation),
            abi.encodeWithSelector(
                FundGovernance.initialize.selector,
                address(factory),
                VOTING_PERIOD,
                QUORUM_PERCENTAGE,
                PROPOSAL_THRESHOLD
            )
        );
        FundGovernance governance = FundGovernance(address(govProxy));

        IIndexFund.TokenAllocation[] memory allocations = new IIndexFund.TokenAllocation[](2);
        allocations[0] = IIndexFund.TokenAllocation({token: WETH, targetPercentage: 6000});
        allocations[1] = IIndexFund.TokenAllocation({token: USDC, targetPercentage: 4000});

        address fundAddress = factory.createFund("Crypto Index Fund", "CIF", USDC, allocations, MANAGEMENT_FEE);

        console.log("Deployed to Base Sepolia:");
        console.log("IndexFund Implementation:", address(fundImplementation));
        console.log("FundFactory Implementation:", address(factoryImplementation));
        console.log("FundGovernance Implementation:", address(governanceImplementation));
        console.log("FundFactory Proxy:", address(factory));
        console.log("FundGovernance Proxy:", address(governance));
        console.log("Initial Fund (CIF):", fundAddress);

        string memory basescanUrl = "https://sepolia.basescan.org/address/";

        vm.writeFile(
            "deployments/base-sepolia.json",
            string(
                abi.encodePacked(
                    '{\n',
                    '  "network": "base-sepolia",\n',
                    '  "chainId": 84532,\n',
                    '  "implementations": {\n',
                    '    "IndexFund": "', vm.toString(address(fundImplementation)), '",\n',
                    '    "FundFactory": "', vm.toString(address(factoryImplementation)), '",\n',
                    '    "FundGovernance": "', vm.toString(address(governanceImplementation)), '"\n',
                    '  },\n',
                    '  "proxies": {\n',
                    '    "FundFactory": "', vm.toString(address(factory)), '",\n',
                    '    "FundGovernance": "', vm.toString(address(governance)), '",\n',
                    '    "CryptoIndexFund": "', vm.toString(fundAddress), '"\n',
                    '  },\n',
                    '  "external": {\n',
                    '    "SwapRouter": "', vm.toString(SWAP_ROUTER), '",\n',
                    '    "WETH": "', vm.toString(WETH), '",\n',
                    '    "USDC": "', vm.toString(USDC), '"\n',
                    '  },\n',
                    '  "verification": {\n',
                    '    "IndexFund": "', basescanUrl, vm.toString(address(fundImplementation)), '",\n',
                    '    "FundFactory": "', basescanUrl, vm.toString(address(factoryImplementation)), '",\n',
                    '    "FundGovernance": "', basescanUrl, vm.toString(address(governanceImplementation)), '",\n',
                    '    "FundFactoryProxy": "', basescanUrl, vm.toString(address(factory)), '",\n',
                    '    "FundGovernanceProxy": "', basescanUrl, vm.toString(address(governance)), '",\n',
                    '    "CryptoIndexFundProxy": "', basescanUrl, vm.toString(fundAddress), '"\n',
                    '  }\n',
                    '}'
                )
            )
        );

        vm.stopBroadcast();
    }
}
