# Transaction History – Parity Plan with Unstoppable

Goal: Replace ad‑hoc history fetch with a robust, adapter‑based pipeline modeled after UnstoppableWallet that works offline/API‑free (Electrum/P2P only), supports pagination, live updates, and consistent UI rendering.

References (local, available anytime):
- UnstoppableWallet/Modules/Transactions
  - TransactionsViewModel.swift
  - Pool/PoolGroupFactory.swift, PoolProvider.swift, PoolGroup.swift, Pool.swift
- UnstoppableWallet/Core
  - Protocols.swift (ITransactionsAdapter)
  - Adapters/BitcoinBaseAdapter.swift (transactionsSingle/Observable, lastBlockInfo, status)
  - Models/TransactionRecords/Bitcoin/* (Incoming/Outgoing/Record)

We can consult Unstoppable’s source in this repo at any time to mirror behavior and interfaces.

## Target Architecture (to mirror)

- Adapter abstraction (Domain): a TransactionsAdapterProtocol similar to ITransactionsAdapter
  - Pagination API: `transactionsSingle(paginationData: String?, limit: Int)`
  - Streaming updates: `transactionsObservable()`
  - Block info: `lastBlockInfo`, `lastBlockUpdatedObservable`
  - Optional: `rawTransaction(hash:)`, `explorerUrl`, etc.

- ElectrumTransactionsAdapter (Core):
  - Source of truth: indexed txids across all owned addresses (external+change)
  - Provides paginated batches and publishes updates on new blocks and scripthash changes
  - No REST APIs; uses Electrum JSON‑RPC (`get_history`, `transaction.get`, `headers.subscribe`)

- Pool/Grouping (Core → Domain):
  - Minimal Pool/PoolGroup to unify multiple sources if needed (per wallet or per blockchain)
  - Provides `itemsSingle(count:)` and invalidation semantics (mirror Unstoppable)

- Transaction decoding (Core/Bitcoin):
  - Parse raw tx hex to structured model (Tx, TxIn, TxOut, locktime)
  - Derive addresses from scriptPubKey (P2WPKH v0, P2PKH; P2SH optional; Taproot later)
  - Compute net value for our wallet (sum owned vouts – sum prevouts of owned vins)

- Presentation mapping (Presentation):
  - Map adapter records to existing `TransactionModel` and current UI sections
  - Keep the UI independent of DI wallets list (already fixed)

## Phased Implementation Plan

### Phase 0 – Cleanup (done)
- Remove REST API clients and any Esplora/Blockstream/Blockchair usage.
- Ensure Electrum calls have `ensureConnected()` + timeouts (history/utxo/verbose) to avoid hangs.

### Phase 1 – Transaction Decoder (Core/Bitcoin)
- Add `TransactionDecoder.swift` with:
  - VarInt reader, LE readers, slice‑safe cursor
  - Parse: version, vin[], vout[], locktime, basic witness capture (optional)
  - ScriptPubKey recognition → address:
    - P2WPKH v0: OP_0 PUSH20
    - P2PKH: OP_DUP OP_HASH160 PUSH20 OP_EQUALVERIFY OP_CHECKSIG
    - P2SH (optional): OP_HASH160 PUSH20 OP_EQUAL
  - Public API: `func decode(rawHex: String) throws -> DecodedTransaction`
- Unit tests (WALL‑ETTests/Core/Bitcoin):
  - Fixtures with 1‑2 known tx hex (mainnet + testnet) → assert #vin/#vout, amounts, addresses
  - Guardrails for malformed payloads

### Phase 2 – ElectrumTransactionsAdapter (Core)
- Domain protocol: `TransactionsAdapterProtocol` in `WALL-ET/Domain/Protocols`
  - `transactionsSingle(paginationData: String?, limit: Int) -> Single<[TransactionRecord]>` (or async/await wrapper)
  - `transactionsObservable() -> Observable<[TransactionRecord]>` (or Combine publisher)
  - `lastBlockInfo: (height:Int, timestamp:Int)?`, `lastBlockUpdatedObservable`

- Implementation in `Core/Adapters/ElectrumTransactionsAdapter.swift`:
  - Index state:
    - `ownedAddresses: [String]` (from repository; gap‑limit ensured)
    - `txIndex: [txid: IndexedTx]` (blockHeight, timestamp, isConfirmed)
    - `sortedTxids: [String]` (desc by blockHeight/time; stable)
  - Inline doc comments in `Core/Adapters/ElectrumTransactionsAdapter.swift` now explain index bootstrap, cache persistence,
    concurrency limits, publisher semantics, and thread-safety expectations at the source.
  - Build index flow:
    - For each address: `get_history` → collect (tx_hash, height)
    - For new txids: fetch raw `transaction.get` (hex) and decode with decoder
    - Compute net value vs. owned set: need prevouts for vins (recursive `transaction.get` + decode, cached)
    - Store `IndexedTx { txid, date, blockHeight, netValue, fee, direction, counterparty }`
  - Pagination semantics:
    - `paginationData` is `lastSeenUid` (txid or a composite `uid`); return next N after that
  - Streaming updates:
    - Subscribe to `ElectrumService.addressStatusPublisher` for owned scripthashes → invalidate/rebuild affected txids
    - Subscribe to `ElectrumService.blockHeightPublisher` → recompute confirmations/status, emit updates
  - Caching:
    - In‑memory LRU for decoded tx + prevout lookup to amortize network calls
    - Optional: lightweight persistence later (Phase 6)

### Phase 3 – Pool/Group (minimal parity)
- Add `Pool`, `PoolProvider`, `PoolGroup` equivalents (subset):
  - `PoolProvider` wraps `ElectrumTransactionsAdapter` as a single provider
  - `Pool` maintains cached `TransactionItem` list and invalidates on provider updates or new blocks
  - `PoolGroup` merges items from providers (single provider in our case) and exposes:
    - `itemsSingle(count:)`, `itemsUpdatedObservable`, `invalidatedObservable`, `syncingObservable`
- Keep parity with Unstoppable interfaces to simplify future multi‑wallet support

### Phase 4 – Presentation Integration
- Add a new `TransactionsStore` that binds the PoolGroup to the SwiftUI view model:
  - `itemsPublisher` → map to existing `TransactionModel`
  - Grouping/sections preserved (already implemented in our `TransactionsViewModel`)
- Update `TransactionsViewModel` to use the adapter pipeline instead of `TransactionService.fetchTransactions` (keep pagination behavior consistent)
- Maintain existing search/filter logic

### Phase 5 – Real‑time Updates & UX polish
- On new block height: recompute confirmations and pending/confirmed state; update rows incrementally
- On address status changes: merge new txids, fetch+decode only the delta, update sections smoothly
- Add “View on Explorer” actions using current network and txid/address

### Phase 6 – Persistence (optional, recommended)
- Persist decoded tx metadata (txid, date, blockHeight, netValue, direction, counterparty) to Core Data
- Warm‑start index on app launch; avoid cold re‑scan
- Migration plan for schema versioning

### Phase 7 – Performance & Resilience
- Batch `get_history` with concurrency limits (TaskGroup + throttling)
- LRU caches for rawTx and prevout txs (size/time bound)
- Reorg handling: watch decreasing/changed heights; re‑sort and re‑emit affected items
- Robust error handling with retries/backoff for transient network issues

## Deliverables & Milestones

1. Decoder ready + tests (Phase 1)
   - Files: `Core/Bitcoin/TransactionDecoder.swift`, tests under `WALL-ETTests/Core/Bitcoin`
2. ElectrumTransactionsAdapter MVP (Phase 2)
   - Files: `Domain/Protocols/TransactionsAdapterProtocol.swift`, `Core/Adapters/ElectrumTransactionsAdapter.swift`
   - In‑memory index for a single wallet; pagination + basic updates
3. Minimal Pool stack (Phase 3)
   - Files: `Core/Transactions/Pool/{PoolProvider,Pool,PoolGroup}.swift`
4. ViewModel wiring (Phase 4)
   - Update `Presentation/ViewModels/TransactionsViewModel.swift` to source from PoolGroup
   - Keep existing UI; ensure empty state logic remains data‑driven
5. Live updates polish (Phase 5)
   - Confirmation counters flow, “pending → confirmed”, address subscription
6. Persistence (Phase 6)
   - Optional in this iteration; improves cold start and reduces Electrum calls
7. Perf & Resilience (Phase 7)
   - Throttling, caches, reorg handling, error policy

## Testing Strategy

- Unit tests:
  - Decoder: raw tx fixtures (segwit v0, legacy P2PKH), malformed cases, big VarInts
  - Net value classifier vs. controlled transaction graphs
- Integration:
  - Electrum test server (mainnet/testnet) with known addresses; assert counts, ordering, and statuses
  - Reorg simulation: mock block heights; verify state transitions
- UI:
  - Snapshot/behavior: list populates without requiring wallets DI, grouping preserved, spinner/empty states correct

## Rollout Plan

- Feature flag: `useNewTxPipeline` in `UserDefaults`
- Dual‑run: compute results both ways (hidden) and log diffs for a limited period
- Once parity is verified, remove old `TransactionService.fetchTransactions` path

## Risks & Mitigations

- Electrum verbose unsupported → We rely on raw hex + local decoding (solved by Phase 1)
- Input prevout fetching cost → LRU cache; defer prevout decode until needed, batch common parents
- Reorgs → subscribe to block headers; recompute affected confirmations and resort
- Performance on large wallets → incremental paging, throttling, and persistence

## Task Breakdown (checklist)

- [x] Implement TransactionDecoder (P2WPKH/P2PKH) — added `Core/Bitcoin/TransactionDecoder.swift`.
  - Done: version/vin/vout/locktime, varint, segwit marker/flag, P2WPKH/P2PKH/P2SH/P2TR script recognition, address derivation by network.
  - Pending: Comprehensive witness parsing (not required for history), additional script types.
- [x] Add TransactionsAdapterProtocol — created `Domain/Protocols/TransactionsAdapterProtocol.swift` (Combine-based).
- [x] Build ElectrumTransactionsAdapter (index, pagination, updates)
  - Implementado índice txid→altura com merge por endereços; paginação por cursor (altura, txid); montagem de TransactionModel via decoder + prevouts; confirmações e timestamp por header; persistência do índice em cache.
- [x] Introduce minimal Pool stack (Provider/Pool/Group)
  - Adicionados: `Core/TransactionsPool/{PoolProvider,Pool,PoolGroup}.swift` (Combine).
- [x] Wire TransactionsViewModel to PoolGroup (+ feature flag)
  - Feature flag `useNewTxPipeline` (UserDefaults). Quando ativo, a VM usa PoolGroup para paginação por count cumulativo.
- [ ] Add live updates from block height + address status
- [x] Core Data persistence for tx metadata
  - `Core/Persistence/Repositories/TransactionMetadataRepository.swift` grava/atualiza TransactionEntity (txid, amount, fee, blockHeight, timestamp, type, status, from/to).
- [x] Perf pass: caching
  - LRU decode cache (512)
  - Header timestamp cache + persistência em Caches (JSON)
  - Intra‑block ordering via `get_merkle.pos` com cache e persistência (JSON)
  - Batch limits/backoff: throttling para history/pos/decodes (6 conc.) e retry exponencial (3 tentativas)
- [ ] Remove legacy service path after parity

### Progress Notes

- Refactor in place to remove REST dependency:
  - Removed Esplora client and all REST calls.
  - TransactionService now builds history using Electrum raw transactions + local decoder (no verbose JSON).
    - New cache for decoded parents to avoid repeated decoding.
    - Fee computed as sum(inputs) - sum(outputs).
    - Confirmations computed using known block heights from address histories + current tip height.
  - Limitations atuais:
    - Cursor usa (altura, txid) mas índice intra‑bloco ainda usa txid como tie‑breaker; evoluir para (height, intraBlockIndex) se necessário.
    - PoolGroup assume único provider; merge multi‑providers pode ser adicionado depois.
    - Retries/backoff e limites de concorrência em lotes ainda não ajustados.

### Toggle & Defaults

- [x] Feature flag exposed in Settings:
  - UI toggle "New Transaction Pipeline" under Preferences (SettingsView).
  - Default enabled via `UserDefaults.register(defaults:)` in `AppCoordinator`.

Notes:
- We can consult the UnstoppableWallet source in this repo at any time to mirror details of `ITransactionsAdapter`, Pool mechanics, and view model behavior.
