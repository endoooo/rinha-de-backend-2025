# Rinha de Backend 2025 - Elixir Project

## Project Context
This is an Elixir application for the "Rinha de backend 2025" challenge. The focus is on learning and understanding Elixir concepts, tools, and best practices.

## Learning-Focused Approach
- **Primary Goal**: Educational - prioritize understanding over speed
- **Explain concepts**: When introducing new Elixir features, patterns, or tools, provide brief explanations
- **Show alternatives**: When applicable, mention different approaches and why we chose one
- **Learning areas to focus on**:
  - Elixir syntax and functional programming patterns
  - Phoenix framework (if web API is required)
  - OTP (Supervisors, GenServers, etc.)
  - Database integration (Ecto)
  - Performance optimization techniques
  - Testing with ExUnit
  - Deployment and containerization

## Technology Stack
- **Language**: Elixir
- **Web Framework**: ~~Phoenix~~ → Bandit + Plug (lightweight HTTP server)
- **Database**: ~~PostgreSQL~~ → In-memory ETS (coordinator-based storage)
- **ORM**: ~~Ecto~~ → Direct ETS operations
- **Testing**: ExUnit
- **Containerization**: Docker (likely required for challenge)

## Code Style Preferences
- Follow Elixir conventions (snake_case, etc.)
- Use pattern matching extensively
- Prefer functional approaches
- Write clear, readable code with appropriate comments for learning
- Use proper error handling with {:ok, result} | {:error, reason} patterns

## Commands to Remember
- `mix new project_name` - Create new project
- `mix deps.get` - Install dependencies
- `mix test` - Run tests
- `docker compose up -d` - Start distributed Erlang cluster
- `iex -S mix` - Start interactive Elixir shell with project loaded

## Challenge Requirements (Rinha de Backend 2025)
**Goal**: Build a payment processing intermediary that maximizes profit by intelligently routing between two processors

**Key APIs to implement**:
- `POST /payments` - Process payment requests (correlationId + amount)
- `GET /payments-summary` - Return processing statistics with optional timestamp filter

**Architecture Constraints**:
- At least 2 web server instances with load balancing
- Expose endpoints on port 9999
- Docker Compose deployment
- Resource limits: 1.5 CPU, 350MB memory total
- Linux-amd64 images, bridge network mode

**Payment Processor Strategy**:
- Default processor (lower fees) vs Fallback processor
- Health check monitoring and intelligent switching
- Handle service instabilities gracefully
- Maximize payments processed during outages

**Scoring**:
- Profit optimization (use lower-fee processor when possible)
- Performance bonus (p99 response time)
- Consistency penalties for payment record mismatches

**Deadline**: August 17, 2025

## API Specifications (Challenge Requirements)

**Backend Endpoints (Port 9999):**
1. `POST /payments`
   - Request: `{"correlationId": "UUID", "amount": decimal}`
   - Response: Any 2XX status code

2. `GET /payments-summary`
   - Query params: `from`, `to` (ISO UTC timestamps, optional)
   - Response: `{"default": {"totalRequests": int, "totalAmount": decimal}, "fallback": {"totalRequests": int, "totalAmount": decimal}}`

**Payment Processor Endpoints:**
1. `POST /payments` - Process payment
   - Request: `{"correlationId": "UUID", "amount": decimal, "requestedAt": "ISO UTC timestamp"}`
   - Response: `{"message": "payment processed successfully"}`

2. `GET /payments/service-health` - Health check
   - Response: `{"failing": boolean, "minResponseTime": integer}`

3. `GET /payments/{id}` - Get payment details

**Processor URLs:**
- Default: `http://payment-processor-default:8080` (lower fees)
- Fallback: `http://payment-processor-fallback:8080` (higher fees)

## Architecture Design

**Core Components:**
1. `PaymentProcessor.HTTPServer` (Bandit + Plug) - Lightweight HTTP endpoints with immediate response
2. `PaymentProcessor.DistributedCoordinatorClient` - Distributed Erlang communication to coordinator
3. `QueueCoordinator.QueueManager` (GenServer) - Centralized payment queue and processing
4. `QueueCoordinator.ProcessorHealthMonitor` (GenServer) - Smart health-based processor selection
5. `QueueCoordinator.Storage` (GenServer) - In-memory ETS aggregated statistics

**Current Data Flow (Distributed Erlang + Immediate Response):**
1. POST /payments → HTTP validation → **immediate 204 response** → async Task.start → distributed GenServer.cast to coordinator
2. Coordinator receives payment → smart health-based processor selection → concurrent processing (6 workers) → ETS storage
3. GET /payments-summary → distributed GenServer.call to coordinator → returns ETS aggregated data

**Previous Data Flow (Original Database Approach):**
1. POST /payments → Controller validates → PaymentRouter selects processor
2. ProcessorClient makes HTTP call → Store result in DB
3. GET /payments-summary → Query DB for aggregated results

**Architecture Status (Aug 14, 2025) - BEST VERSION ACHIEVED:**
- ✅ 0 inconsistencies maintained with distributed Erlang coordination
- ✅ 0 timeout failures with immediate response pattern  
- ✅ Perfect reliability (no failed requests) with optimized latency
- ✅ **BREAKTHROUGH**: Default-first strategy achieved optimal profit optimization
- ✅ **534 fallback requests** (vs target 576) - **82% reduction** from problematic 2911
- ✅ **11562 default requests** - maximized use of 5% fee processor
- ✅ **240710.4 total throughput** - **13% higher** than previous best
- 3-container setup: coordinator (150MB) + api1/api2 (90MB each) + nginx (20MB) = **350MB total**
- Distributed Erlang cluster with ERL_COOKIE authentication and EPMD discovery
- Immediate HTTP 204 response + async payment processing for minimal user-perceived latency
- **Default-first routing**: Always try default processor, fallback only as true backup when default fails AND fallback healthy (≤50ms)

## Documentation Process
**Interaction History**: Update `CLAUDE_CODE_INTERACTIONS_HISTORY.md` after significant milestones
- Format: Date - Brief Description, Context (one-line), Action (what was done), Learning (key concept)
- Focus on learning outcomes and major implementation steps
- Keep entries minimal but informative for future reference

## Local Testing Instructions (Rinha Challenge)

**Prerequisites:**
- Install k6 following official k6 installation instructions
- Download rinha-test directory from challenge repository

**Testing Steps:**
1. Start backend containers: `docker compose up -d` 
2. Navigate to rinha-test directory
3. Run basic test: `k6 run rinha.js`
4. Optional: Customize requests: `k6 run -e MAX_REQUESTS=550 rinha.js`
5. Optional: Enable dashboard: `export K6_WEB_DASHBOARD=true && export K6_WEB_DASHBOARD_EXPORT='report.html'`

**Note:** Test uses k6 for performance testing, focusing on concurrent request handling

## Key Performance Optimizations Implemented

**Phase 1: Phoenix Removal & Immediate Response**
- Replaced Phoenix with Bandit + Plug for minimal HTTP overhead
- Implemented immediate HTTP 204 response pattern (like winning competitor)
- Async Task.start for fire-and-forget payment processing

**Phase 2: Smart Health-Based Routing**
- ProcessorHealthMonitor with 5-second polling intervals
- Performance thresholds: default ≤100ms, fallback ≤50ms
- Skip slow processors rather than use expensive fallback
- Minimize 15% fallback fees, maximize 5% default processor usage

**Phase 3: Distributed Erlang Architecture**
- Direct GenServer communication across containers (Node.connect)
- ERL_COOKIE cluster authentication
- Eliminated HTTP coordinator bottleneck with distributed calls
- Perfect consistency (0 inconsistencies) + zero failures

**Resource Optimization:**
- Exact challenge compliance: 350MB memory, 1.5 CPU
- Production Elixir releases for memory efficiency
- Optimized connection pools and BEAM VM tuning