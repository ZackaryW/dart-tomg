## ADDED Requirements

### Requirement: Declared generator dependency lower bounds are verified

The generator package SHALL declare version ranges for its analyzer, source
generation, and formatter dependencies that any verified stack can satisfy.
Automated verification SHALL resolve the workspace with each of those
dependencies at its lowest declared version and SHALL run the generator,
consumer, and example gates against that stack as well as the default
resolution. Generated output SHALL be identical across the two stacks.

#### Scenario: Lowest-bounds stack passes

- **WHEN** verification resolves the declared lowest analyzer, source
  generation, and formatter versions
- **THEN** generator tests, consumer tests, and example generation succeed, and
  regenerated example output matches the checked-in files

#### Scenario: A lower bound is no longer satisfiable

- **WHEN** a code change uses an API that is missing at a declared lower bound
- **THEN** the lowest-bounds job fails, and the lower bound must be raised or
  the code must be changed before release

#### Scenario: Consumer on an older analyzer resolves the published generator

- **WHEN** a consuming package whose other dev dependencies cap the analyzer
  at 10.x adds the published generator
- **THEN** dependency resolution succeeds without dependency overrides
