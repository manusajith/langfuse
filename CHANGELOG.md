# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `Langfuse.Prompt.get/2` now returns prompt data correctly; the underlying HTTP call was sending the prompt name as a query parameter instead of in the URL path

### Changed
- Relaxed Elixir version constraint from `~> 1.19` to `~> 1.17` to support projects on Elixir 1.17 and 1.18

### Added
- `:resolve` option for `Langfuse.Prompt.get/2`, `Langfuse.Prompt.fetch/2`, `Langfuse.Client.get_prompt/2`, and `Langfuse.HTTP.get_prompt/2` to control server-side prompt dependency resolution
- `:cacertfile` config option and `LANGFUSE_CACERTFILE` env var for custom CA certificates (self-hosted Langfuse with self-signed certs)
- GitHub Actions CI with matrix testing across Elixir 1.17/OTP 26, 1.18/OTP 27, and 1.19/OTP 28

## [0.1.0] - 2025-11-29

### Added

#### Core Tracing
- `Langfuse.trace/1` for creating traces with version and release field support
- `Langfuse.span/2` for creating spans with observation types (agent, tool, chain, retriever, embedding, etc.)
- `Langfuse.generation/2` for tracking LLM generations with flexible usage fields
- `Langfuse.event/2` for recording discrete events
- Environment field support across all event payloads
- SDK metadata included in ingestion batch requests

#### Scoring
- `Langfuse.score/2` with numeric, categorical, and boolean score types
- Session ID and metadata support for scores

#### Sessions
- `Langfuse.Session` for grouping related traces into conversations

#### Prompt Management
- `Langfuse.Prompt.get/2` for fetching prompts with automatic caching
- `Langfuse.Prompt.compile/2` for variable substitution in prompts
- Fallback prompt support when fetch fails
- Cache invalidation functions (`invalidate/2`, `invalidate_all/0`)

#### Client API
- `Langfuse.Client` module for direct REST API access
- `auth_check/0` for connection verification
- Prompts API: `get_prompt/2`
- Datasets API: create, get, list, delete datasets and items
- Dataset items: create, get, update (PATCH), delete
- Dataset runs: create and get
- Observations API: get and list observations
- Models API: create, get, list, delete models
- Score configs API: create, get, list

#### OpenTelemetry Integration
- Optional OpenTelemetry dependency integration
- `Langfuse.OpenTelemetry.SpanProcessor` for converting OTEL spans to Langfuse observations
- `Langfuse.OpenTelemetry.TraceContext` for W3C distributed tracing
- `Langfuse.OpenTelemetry.AttributeMapper` for field mapping
- `Langfuse.OpenTelemetry.Setup` module for configuration helpers

#### Instrumentation
- `Langfuse.Instrumentation` macros for automatic function tracing
- Custom instrumentation support via telemetry

#### Security
- `Langfuse.Masking` module for sensitive data redaction
- Configurable masking patterns and functions

#### Infrastructure
- `Langfuse.Ingestion` GenServer for async event batching
- Configurable batch size, flush intervals, and retry settings
- Graceful shutdown with automatic pending event flush
- `Langfuse.Config` with `reload/0` for runtime configuration updates
- Configurable GenServer names for multi-instance support
- HTTP client with exponential backoff retry
- Debug logging configuration option

#### Telemetry
- `Langfuse.Telemetry` events for observability:
  - `[:langfuse, :ingestion, :flush, :start | :stop | :exception]`
  - `[:langfuse, :http, :request, :start | :stop | :exception]`
  - `[:langfuse, :prompt, :fetch, :start | :stop | :exception]`
  - `[:langfuse, :prompt, :cache, :hit | :miss]`

