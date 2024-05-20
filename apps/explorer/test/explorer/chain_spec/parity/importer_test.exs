defmodule Explorer.ChainSpec.Parity.ImporterTest do
  use Explorer.DataCase

  import Mox
  import EthereumJSONRPC, only: [integer_to_quantity: 1]

  alias Explorer.Chain.Address.{CoinBalance, CoinBalanceDaily}
  alias Explorer.Chain.Block.{EmissionReward, Range}
  alias Explorer.Chain.{Address, Hash, Wei}
  alias Explorer.ChainSpec.Parity.Importer
  alias Explorer.Repo

  setup :set_mox_global

  setup :verify_on_exit!

  @chain_spec "#{File.cwd!()}/test/support/fixture/chain_spec/foundation.json"
              |> File.read!()
              |> Jason.decode!()

  @chain_classic_spec "#{File.cwd!()}/test/support/fixture/chain_spec/classic.json"
                      |> File.read!()
                      |> Jason.decode!()

  describe "emission_rewards/1" do
    test "fetches and formats reward ranges" do
      assert Importer.emission_rewards(@chain_spec) == [
               %{
                 block_range: %Range{from: 0, to: 4_370_000},
                 reward: %Wei{value: Decimal.new(5_000_000_000_000_000_000)}
               },
               %{
                 block_range: %Range{from: 4_370_001, to: 7_280_000},
                 reward: %Wei{value: Decimal.new(3_000_000_000_000_000_000)}
               },
               %{
                 block_range: %Range{from: 7_280_001, to: :infinity},
                 reward: %Wei{value: Decimal.new(2_000_000_000_000_000_000)}
               }
             ]
    end

    test "fetches and formats a single reward" do
      assert Importer.emission_rewards(@chain_classic_spec) == [
               %{
                 block_range: %Range{from: 1, to: :infinity},
                 reward: %Wei{value: Decimal.new(5_000_000_000_000_000_000)}
               }
             ]
    end
  end

  describe "import_emission_rewards/1" do
    test "inserts emission rewards from chain spec" do
      assert {3, nil} = Importer.import_emission_rewards(@chain_spec)
    end

    test "rewrites all recorded" do
      old_block_rewards = %{
        "0x0" => "0x1bc16d674ec80000",
        "0x42ae50" => "0x29a2241af62c0000",
        "0x6f1580" => "0x4563918244f40000"
      }

      chain_spec = %{
        @chain_spec
        | "engine" => %{
            @chain_spec["engine"]
            | "Ethash" => %{
                @chain_spec["engine"]["Ethash"]
                | "params" => %{@chain_spec["engine"]["Ethash"]["params"] | "blockReward" => old_block_rewards}
              }
          }
      }

      assert {3, nil} = Importer.import_emission_rewards(chain_spec)
      [first, second, third] = Repo.all(EmissionReward)

      assert first.reward == %Wei{value: Decimal.new(2_000_000_000_000_000_000)}
      assert first.block_range == %Range{from: 0, to: 4_370_000}

      assert second.reward == %Wei{value: Decimal.new(3_000_000_000_000_000_000)}
      assert second.block_range == %Range{from: 4_370_001, to: 7_280_000}

      assert third.reward == %Wei{value: Decimal.new(5_000_000_000_000_000_000)}
      assert third.block_range == %Range{from: 7_280_001, to: :infinity}

      assert {3, nil} = Importer.import_emission_rewards(@chain_spec)
      [new_first, new_second, new_third] = Repo.all(EmissionReward)

      assert new_first.reward == %Wei{value: Decimal.new(5_000_000_000_000_000_000)}
      assert new_first.block_range == %Range{from: 0, to: 4_370_000}

      assert new_second.reward == %Wei{value: Decimal.new(3_000_000_000_000_000_000)}
      assert new_second.block_range == %Range{from: 4_370_001, to: 7_280_000}

      assert new_third.reward == %Wei{value: Decimal.new(2_000_000_000_000_000_000)}
      assert new_third.block_range == %Range{from: 7_280_001, to: :infinity}
    end
  end

  describe "genesis_accounts/1" do
    test "parses coin balance" do
      coin_balances = Importer.genesis_accounts(@chain_spec)

      assert Enum.count(coin_balances) == 403

      assert %{
               address_hash: %Hash{
                 byte_count: 20,
                 bytes: <<167, 105, 41, 137, 10, 123, 71, 251, 133, 145, 150, 1, 108, 111, 221, 130, 137, 206, 183, 85>>
               },
               value: 5_000_000_000_000_000_000_000,
               contract_code: nil,
               nonce: 0
             } ==
               List.first(coin_balances)
    end

    test "parses nonce and contact code" do
      code =
        "0x608060405234801561001057600080fd5b50600436106100cf5760003560e01c806391ad27b41161008c57806398d5fdca1161006657806398d5fdca14610262578063a97e5c9314610280578063df5dd1a5146102dc578063eebd48b014610320576100cf565b806391ad27b4146101e457806391b7f5ed14610202578063955d14cd14610244576100cf565b80630aa6f2fe146100d457806320ba81ee1461011657806322a90082146101345780634c2c987c14610176578063764cbcd1146101985780637837efdc146101da575b600080fd5b610100600480360360208110156100ea57600080fd5b8101908080359060200190929190505050610353565b6040518082815260200191505060405180910390f35b61011e6103c4565b6040518082815260200191505060405180910390f35b6101606004803603602081101561014a57600080fd5b81019080803590602001909291905050506103ce565b6040518082815260200191505060405180910390f35b61017e61043f565b604051808215151515815260200191505060405180910390f35b6101c4600480360360208110156101ae57600080fd5b8101908080359060200190929190505050610456565b6040518082815260200191505060405180910390f35b6101e26104c7565b005b6101ec6104d2565b6040518082815260200191505060405180910390f35b61022e6004803603602081101561021857600080fd5b81019080803590602001909291905050506104dc565b6040518082815260200191505060405180910390f35b61024c6106a2565b6040518082815260200191505060405180910390f35b61026a6106ac565b6040518082815260200191505060405180910390f35b6102c26004803603602081101561029657600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506106b6565b604051808215151515815260200191505060405180910390f35b61031e600480360360208110156102f257600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506106d3565b005b61032861073d565b6040518085815260200184815260200183815260200182815260200194505050505060405180910390f35b600061035e336106b6565b6103b3576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816004819055506004549050919050565b6000600454905090565b60006103d9336106b6565b61042e576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816003819055506003549050919050565b6000600560009054906101000a900460ff16905090565b6000610461336106b6565b6104b6576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816002819055506002549050919050565b6104d033610771565b565b6000600354905090565b60006104e7336106b6565b61053c576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b600082116105b2576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260098152602001807f7072696365203c3d30000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b6105ba6104d2565b6105c26106a2565b01421015610638576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260148152602001807f54494d455f4c4f434b5f494e434f4d504c45544500000000000000000000000081525060200191505060405180910390fd5b610641826107cb565b5061064b42610456565b503373ffffffffffffffffffffffffffffffffffffffff167f95dce27040c59c8b1c445b284f81a3aaae6eecd7d08d5c7684faee64cdb514a1836040518082815260200191505060405180910390a2819050919050565b6000600254905090565b6000600154905090565b60006106cc82600061083c90919063ffffffff16565b9050919050565b6106dc336106b6565b610731576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b61073a8161091a565b50565b60008060008061074b6106ac565b6107536104d2565b61075b6103c4565b6107636106a2565b935093509350935090919293565b61078581600061097390919063ffffffff16565b8073ffffffffffffffffffffffffffffffffffffffff167f9c8e7d83025bef8a04c664b2f753f64b8814bdb7e27291d7e50935f18cc3c71260405160405180910390a250565b60006107d6336106b6565b61082b576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816001819055506001549050919050565b60008073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614156108c3576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526022815260200180610b2d6022913960400191505060405180910390fd5b8260000160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900460ff16905092915050565b61092e816000610a3090919063ffffffff16565b8073ffffffffffffffffffffffffffffffffffffffff167e47706786c922d17b39285dc59d696bafea72c0b003d3841ae1202076f4c2e460405160405180910390a250565b61097d828261083c565b6109d2576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526021815260200180610b0c6021913960400191505060405180910390fd5b60008260000160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548160ff0219169083151502179055505050565b610a3a828261083c565b15610aad576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252601f8152602001807f526f6c65733a206163636f756e7420616c72656164792068617320726f6c650081525060200191505060405180910390fd5b60018260000160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548160ff021916908315150217905550505056fe526f6c65733a206163636f756e7420646f6573206e6f74206861766520726f6c65526f6c65733a206163636f756e7420697320746865207a65726f20616464726573734f7261636c65526f6c653a2063616c6c657220646f6573206e6f74206861766520746865204f7261636c6520726f6c65a265627a7a72315820df30730da57a5061c487e0b37e84e80308fa443e2e80ee9117a13fa8149caf4164736f6c634300050b0032"

      chain_spec = %{
        "accounts" => %{
          "0xcd59f3dde77e09940befb6ee58031965cae7a336" => %{
            "balance" => "0x21e19e0c9bab2400000",
            "constructor" => code
          }
        }
      }

      accounts = Importer.genesis_accounts(chain_spec)

      assert accounts == [
               %{
                 address_hash: %Explorer.Chain.Hash{
                   byte_count: 20,
                   bytes: <<205, 89, 243, 221, 231, 126, 9, 148, 11, 239, 182, 238, 88, 3, 25, 101, 202, 231, 163, 54>>
                 },
                 contract_code: code,
                 nonce: 0,
                 value: 10_000_000_000_000_000_000_000
               }
             ]
    end
  end

  describe "import_genesis_accounts/1" do
    test "imports accounts" do
      block_quantity = integer_to_quantity(1)
      res = eth_block_number_fake_response(block_quantity)

      EthereumJSONRPC.Mox
      |> expect(:json_rpc, fn [
                                %{id: 0, jsonrpc: "2.0", method: "eth_getBlockByNumber", params: ["0x1", true]}
                              ],
                              _ ->
        {:ok, [res]}
      end)

      {:ok, %{address_coin_balances: address_coin_balances}} = Importer.import_genesis_accounts(@chain_spec)

      assert Enum.count(address_coin_balances) == 403
      assert CoinBalance |> Repo.all() |> Enum.count() == 403
      assert CoinBalanceDaily |> Repo.all() |> Enum.count() == 403
      assert Address |> Repo.all() |> Enum.count() == 403
    end

    test "imports contract code" do
      block_quantity = integer_to_quantity(1)
      res = eth_block_number_fake_response(block_quantity)

      EthereumJSONRPC.Mox
      |> expect(:json_rpc, fn [
                                %{id: 0, jsonrpc: "2.0", method: "eth_getBlockByNumber", params: ["0x1", true]}
                              ],
                              [] ->
        {:ok, [res]}
      end)

      code =
        "0x608060405234801561001057600080fd5b50600436106100cf5760003560e01c806391ad27b41161008c57806398d5fdca1161006657806398d5fdca14610262578063a97e5c9314610280578063df5dd1a5146102dc578063eebd48b014610320576100cf565b806391ad27b4146101e457806391b7f5ed14610202578063955d14cd14610244576100cf565b80630aa6f2fe146100d457806320ba81ee1461011657806322a90082146101345780634c2c987c14610176578063764cbcd1146101985780637837efdc146101da575b600080fd5b610100600480360360208110156100ea57600080fd5b8101908080359060200190929190505050610353565b6040518082815260200191505060405180910390f35b61011e6103c4565b6040518082815260200191505060405180910390f35b6101606004803603602081101561014a57600080fd5b81019080803590602001909291905050506103ce565b6040518082815260200191505060405180910390f35b61017e61043f565b604051808215151515815260200191505060405180910390f35b6101c4600480360360208110156101ae57600080fd5b8101908080359060200190929190505050610456565b6040518082815260200191505060405180910390f35b6101e26104c7565b005b6101ec6104d2565b6040518082815260200191505060405180910390f35b61022e6004803603602081101561021857600080fd5b81019080803590602001909291905050506104dc565b6040518082815260200191505060405180910390f35b61024c6106a2565b6040518082815260200191505060405180910390f35b61026a6106ac565b6040518082815260200191505060405180910390f35b6102c26004803603602081101561029657600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506106b6565b604051808215151515815260200191505060405180910390f35b61031e600480360360208110156102f257600080fd5b81019080803573ffffffffffffffffffffffffffffffffffffffff1690602001909291905050506106d3565b005b61032861073d565b6040518085815260200184815260200183815260200182815260200194505050505060405180910390f35b600061035e336106b6565b6103b3576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816004819055506004549050919050565b6000600454905090565b60006103d9336106b6565b61042e576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816003819055506003549050919050565b6000600560009054906101000a900460ff16905090565b6000610461336106b6565b6104b6576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816002819055506002549050919050565b6104d033610771565b565b6000600354905090565b60006104e7336106b6565b61053c576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b600082116105b2576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260098152602001807f7072696365203c3d30000000000000000000000000000000000000000000000081525060200191505060405180910390fd5b6105ba6104d2565b6105c26106a2565b01421015610638576040517f08c379a00000000000000000000000000000000000000000000000000000000081526004018080602001828103825260148152602001807f54494d455f4c4f434b5f494e434f4d504c45544500000000000000000000000081525060200191505060405180910390fd5b610641826107cb565b5061064b42610456565b503373ffffffffffffffffffffffffffffffffffffffff167f95dce27040c59c8b1c445b284f81a3aaae6eecd7d08d5c7684faee64cdb514a1836040518082815260200191505060405180910390a2819050919050565b6000600254905090565b6000600154905090565b60006106cc82600061083c90919063ffffffff16565b9050919050565b6106dc336106b6565b610731576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b61073a8161091a565b50565b60008060008061074b6106ac565b6107536104d2565b61075b6103c4565b6107636106a2565b935093509350935090919293565b61078581600061097390919063ffffffff16565b8073ffffffffffffffffffffffffffffffffffffffff167f9c8e7d83025bef8a04c664b2f753f64b8814bdb7e27291d7e50935f18cc3c71260405160405180910390a250565b60006107d6336106b6565b61082b576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526030815260200180610b4f6030913960400191505060405180910390fd5b816001819055506001549050919050565b60008073ffffffffffffffffffffffffffffffffffffffff168273ffffffffffffffffffffffffffffffffffffffff1614156108c3576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526022815260200180610b2d6022913960400191505060405180910390fd5b8260000160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060009054906101000a900460ff16905092915050565b61092e816000610a3090919063ffffffff16565b8073ffffffffffffffffffffffffffffffffffffffff167e47706786c922d17b39285dc59d696bafea72c0b003d3841ae1202076f4c2e460405160405180910390a250565b61097d828261083c565b6109d2576040517f08c379a0000000000000000000000000000000000000000000000000000000008152600401808060200182810382526021815260200180610b0c6021913960400191505060405180910390fd5b60008260000160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548160ff0219169083151502179055505050565b610a3a828261083c565b15610aad576040517f08c379a000000000000000000000000000000000000000000000000000000000815260040180806020018281038252601f8152602001807f526f6c65733a206163636f756e7420616c72656164792068617320726f6c650081525060200191505060405180910390fd5b60018260000160008373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060006101000a81548160ff021916908315150217905550505056fe526f6c65733a206163636f756e7420646f6573206e6f74206861766520726f6c65526f6c65733a206163636f756e7420697320746865207a65726f20616464726573734f7261636c65526f6c653a2063616c6c657220646f6573206e6f74206861766520746865204f7261636c6520726f6c65a265627a7a72315820df30730da57a5061c487e0b37e84e80308fa443e2e80ee9117a13fa8149caf4164736f6c634300050b0032"

      chain_spec = %{
        "accounts" => %{
          "0xcd59f3dde77e09940befb6ee58031965cae7a336" => %{
            "balance" => "0x21e19e0c9bab2400000",
            "constructor" => code
          }
        }
      }

      {:ok, _} = Importer.import_genesis_accounts(chain_spec)

      address = Address |> Repo.one()

      assert to_string(address.contract_code) == code
    end

    test "imports coin balances without 0x" do
      block_quantity = integer_to_quantity(1)
      res = eth_block_number_fake_response(block_quantity)

      EthereumJSONRPC.Mox
      |> expect(:json_rpc, fn [
                                %{id: 0, jsonrpc: "2.0", method: "eth_getBlockByNumber", params: ["0x1", true]}
                              ],
                              [] ->
        {:ok, [res]}
      end)

      {:ok, %{address_coin_balances: address_coin_balances}} = Importer.import_genesis_accounts(@chain_classic_spec)

      assert Enum.count(address_coin_balances) == 8894
      assert CoinBalance |> Repo.all() |> Enum.count() == 8894
      assert CoinBalanceDaily |> Repo.all() |> Enum.count() == 8894
      assert Address |> Repo.all() |> Enum.count() == 8894
    end
  end

  defp eth_block_number_fake_response(block_quantity) do
    %{
      id: 0,
      jsonrpc: "2.0",
      result: %{
        "author" => "0x0000000000000000000000000000000000000000",
        "difficulty" => "0x20000",
        "extraData" => "0x",
        "gasLimit" => "0x663be0",
        "gasUsed" => "0x0",
        "hash" => "0x5b28c1bfd3a15230c9a46b399cd0f9a6920d432e85381cc6a140b06e8410112f",
        "logsBloom" =>
          "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "miner" => "0x0000000000000000000000000000000000000000",
        "number" => block_quantity,
        "parentHash" => "0x0000000000000000000000000000000000000000000000000000000000000000",
        "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
        "sealFields" => [
          "0x80",
          "0xb8410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        ],
        "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
        "signature" =>
          "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        "size" => "0x215",
        "stateRoot" => "0xfad4af258fd11939fae0c6c6eec9d340b1caac0b0196fd9a1bc3f489c5bf00b3",
        "step" => "0",
        "timestamp" => "0x0",
        "totalDifficulty" => "0x20000",
        "transactions" => [],
        "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
        "uncles" => []
      }
    }
  end
end