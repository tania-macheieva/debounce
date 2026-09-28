# Debouncer

A thread-safe Ruby implementation of the **Debounce pattern** for delaying function execution until a specified period of inactivity has passed.

Debouncing is useful for controlling frequent events such as user input, search requests, API calls, or other operations that may be triggered repeatedly within a short period of time.

### How it works

Each call to the debounced function resets the timer. The wrapped function is executed only after no new calls have been received during the configured delay.

The implementation supports two execution modes:

* **Leading** — execute immediately on the first call of a burst.
* **Trailing** — execute after the burst ends, using the arguments from the last call.

Both modes can be enabled simultaneously.

### Features

* Configurable debounce delay in milliseconds
* `leading` and `trailing` execution modes
* Preserves arguments and blocks passed to the debounced function
* Thread-safe synchronization using `Monitor`
* Real asynchronous scheduler based on Ruby threads
* Cancellable scheduled tasks using `Mutex` and `ConditionVariable`
* `dispose` support for cancelling pending executions
* Injectable scheduler for deterministic testing
* Fake scheduler for testing without real time delays

### Tests

The RSpec test suite covers:

* Default trailing debounce behavior
* Suppression of rapid consecutive calls
* Resetting the timer after each call
* Separate execution of independent bursts
* Leading-only behavior
* Leading + trailing behavior
* Argument and block forwarding
* Constructor validation
* Cancelling pending calls with `dispose`
* Starting a fresh burst after disposal
* Real-time asynchronous execution
* Concurrent calls racing with timer execution

The project separates the debounce logic from scheduling, which makes the core behavior deterministic and easy to test while still providing a real-time scheduler for production use.
