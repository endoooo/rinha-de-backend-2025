# Rinha de Backend 2025 - Elixir Solution

High-performance payment processing intermediary built with Elixir for the Rinha de Backend 2025 challenge.

## Current Architecture

**HTTP Coordinator Architecture (3-Container Setup):**
- `coordinator` service: Centralized queue management with ETS storage and concurrent processing
- `api1` & `api2` services: HTTP endpoints that communicate with coordinator 
- `nginx`: Load balancer for API instances

**Status (Aug 13, 2025):**
- ✅ 0 inconsistencies achieved
- ✅ 0 timeout failures with concurrent processing
- ⚠️ Low scoring despite perfect reliability (24% lower throughput than best version)

## Performance Optimization Roadmap

### 1. **Remove Phoenix Framework Overhead** (🚧 IN PROGRESS)
- Replace Phoenix with bare-metal Elixir HTTP server (Bandit directly)
- Eliminate Phoenix router, controller, and middleware layers
- Use simple Plug pipeline for minimal HTTP handling
- **Target**: 30-50% latency reduction for API endpoints

### 2. **Optimize Coordinator Communication** (📋 PLANNED)
- Replace HTTP coordinator calls with lighter alternatives:
  - Option A: Shared ETS table with file-backed persistence
  - Option B: Direct GenServer calls via Node.connect for distributed Erlang
  - Option C: Minimal HTTP with persistent connections and request pipelining
- **Target**: 20-40% reduction in request processing time

### 3. **Aggressive Performance Tuning** (📋 PLANNED)
- Increase concurrent workers from 6 to 10-12 
- Optimize connection pools: increase to 50+ connections per processor
- Tune BEAM VM flags for maximum throughput over latency
- Pre-warm connection pools and optimize keepalive settings
- **Target**: 15-25% throughput improvement

### 4. **Smart Batching and Processor Selection** (📋 PLANNED)
- Implement intelligent processor health monitoring
- Batch multiple payments to same processor in single HTTP call
- Optimize default vs fallback routing logic for maximum fee efficiency
- **Target**: 10-20% better processor utilization

### 5. **Resource Reallocation** (📋 PLANNED)
- Optimize memory allocation: reduce coordinator memory, increase API instances
- Consider 3 smaller API instances instead of 2 larger ones
- Fine-tune CPU allocation based on bottleneck analysis
- **Target**: 5-10% better resource utilization

## Performance Targets

**Current Performance:**
- Throughput: $191K total transactions
- Successful transactions: 11,679
- Inconsistencies: 0 (perfect)
- P99 response time: ~1.5s

**Target Performance:**
- **Throughput**: Increase to $230K+ (20%+ improvement)
- **Consistency**: Maintain 0 inconsistencies (critical)
- **P99 latency**: Reduce to <500ms for performance bonus
- **Resource efficiency**: Stay within 1.5 CPU, 350MB memory limits

## Challenge Scoring System

Based on challenge rules:
1. **Primary Metric**: Profit maximization (total payments with lowest fees)
2. **Performance Bonus**: `(11 - p99_ms) * 0.02` (up to 20% bonus for <1ms p99)
3. **Consistency Penalty**: 35% deduction if inconsistencies detected

## Quick Start

```bash
# Start all services
docker compose up -d

# Run load test
cd rinha-test
k6 run rinha.js

# Check status
curl http://localhost:9999/payments-summary
```

## Architecture Details

See `CLAUDE.md` for detailed technical documentation and implementation history.
