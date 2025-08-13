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
- **Web Framework**: Phoenix (if needed)
- **Database**: PostgreSQL (typical for challenges)
- **ORM**: Ecto
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
- `mix phx.server` - Start Phoenix server (if using Phoenix)
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
1. `PaymentProcessor.ProcessorMonitor` (GenServer) - Tracks processor health status
2. `PaymentProcessor.PaymentRouter` - Routes payments to best available processor 
3. `PaymentProcessor.ProcessorClient` - HTTP client for processor communication
4. `PaymentProcessor.Payments` - Context for payment business logic
5. `PaymentProcessorWeb.PaymentController` - API endpoints

**Current Data Flow (HTTP Coordinator Architecture):**
1. POST /payments → API Controller validates → HTTP call to coordinator → immediate response
2. Coordinator manages centralized ETS queue → processes payments in order → updates aggregated stats
3. GET /payments-summary → HTTP call to coordinator → returns aggregated data

**Previous Data Flow (Original Database Approach):**
1. POST /payments → Controller validates → PaymentRouter selects processor
2. ProcessorClient makes HTTP call → Store result in DB
3. GET /payments-summary → Query DB for aggregated results

**Architecture Status (Aug 13, 2025):**
- ✅ 0 inconsistencies achieved with HTTP coordinator
- ✅ 0 timeout failures with concurrent processing (resolved bottleneck)
- ⚠️ Load test shows low scoring despite perfect reliability (needs performance investigation)
- 3-container setup: coordinator (200MB) + api1/api2 (150MB each) + nginx (20MB)
- Production releases with BEAM VM tuning and concurrent processing (6 workers)
- HTTP connection pools: 20 connections per processor, optimized TCP settings

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
1. Start backend containers: `docker-compose up -d` 
2. Navigate to rinha-test directory
3. Run basic test: `k6 run rinha.js`
4. Optional: Customize requests: `k6 run -e MAX_REQUESTS=550 rinha.js`
5. Optional: Enable dashboard: `export K6_WEB_DASHBOARD=true && export K6_WEB_DASHBOARD_EXPORT='report.html'`

**Note:** Test uses k6 for performance testing, focusing on concurrent request handling

## Challenge Preparation Notes
- Performance will likely be a key metric (p99 response times)
- Database optimization may be crucial for payment tracking
- Proper error handling and processor failover logic
- Docker configuration for deployment with strict resource limits
- Load testing preparation for payment processing under load