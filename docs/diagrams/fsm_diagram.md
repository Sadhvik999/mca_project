# Cache controller FSM

```mermaid
stateDiagram-v2
    [*] --> IDLE: reset
    IDLE --> IDLE: no request
    IDLE --> COMPARE_TAG: latch CPU request
    COMPARE_TAG --> IDLE: tag hit / complete CPU request
    COMPARE_TAG --> WRITE_BACK: miss with valid, dirty victim
    COMPARE_TAG --> ALLOCATE: miss with invalid or clean victim
    WRITE_BACK --> WRITE_BACK: wait for mem_ready
    WRITE_BACK --> ALLOCATE: mem_ready / write-back complete
    ALLOCATE --> ALLOCATE: wait for mem_ready
    ALLOCATE --> COMPARE_TAG: mem_ready / fill line and retry
```

| State | Condition | Next state | Actions / outputs |
| --- | --- | --- | --- |
| Any | `rst` at rising edge | `IDLE` | Reset the controller and clear cache metadata. |
| `IDLE` | `req = 0` | `IDLE` | Wait for a request. |
| `IDLE` | `req = 1` | `COMPARE_TAG` | Latch `addr`, `we`, and `wdata`. |
| `COMPARE_TAG` | Valid tag match, read | `IDLE` | Return the word selected by `addr[3:2]` and assert `ready`. |
| `COMPARE_TAG` | Valid tag match, write | `IDLE` | Enable the selected word write and set dirty at the clock edge. Assert `ready`. |
| `COMPARE_TAG` | Miss, valid and dirty victim | `WRITE_BACK` | Assert `miss` and `dirty_evict`. |
| `COMPARE_TAG` | Miss, invalid or clean victim | `ALLOCATE` | Assert `miss`. |
| `WRITE_BACK` | `mem_ready = 0` | `WRITE_BACK` | Hold the block write request with the victim tag, index, and zero offset. |
| `WRITE_BACK` | `mem_ready = 1` | `ALLOCATE` | Finish the block write and advance directly to the refill. |
| `ALLOCATE` | `mem_ready = 0` | `ALLOCATE` | Hold the block read request with the requested tag, index, and zero offset. |
| `ALLOCATE` | `mem_ready = 1` | `COMPARE_TAG` | Install the returned block and requested tag. Set valid, clear dirty, and retry the latched operation. |

The FSM is Mealy. In `COMPARE_TAG`, `ready` depends on the tag comparison.
In `ALLOCATE`, the array fill enables depend on `mem_ready`. The memory request
direction is decoded from state. The memory model ignores requests on its
completion edge, then accepts the next request in its idle state.

Drive `req` with the request operands before a rising edge in `IDLE`. Sample
`ready` and read data at a rising edge, and release the completed request before
the next rising edge. State encodings are `IDLE=0`, `COMPARE_TAG=1`,
`WRITE_BACK=2`, `ALLOCATE=3`. The `hit`, `miss`, and `dirty_evict` debug
signals describe the initial comparison. A refill retry completes with `ready`
and produces no second hit/miss event.
