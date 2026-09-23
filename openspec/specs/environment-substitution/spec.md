# environment-substitution Specification

## Purpose

Resolve explicit TOML string references from the build process environment into
typed constants, with deterministic defaults, escaping, and contextual errors.

## Requirements

### Requirement: Environment reference syntax

The generator SHALL interpret a complete TOML string matching `$VAR` as a
required reference to the build process environment, where `VAR` matches
`[A-Za-z_][A-Za-z0-9_]*`. It SHALL interpret `$VAR=default` as the same lookup
with the text after the first `=` as a literal fallback used only when `VAR` is
absent.

#### Scenario: Required variable is present

- **WHEN** a TOML value is `$API_URL` and `API_URL` exists in the generator
  process environment
- **THEN** the generated field uses the environment value

#### Scenario: Required variable is absent

- **WHEN** a TOML value is `$API_URL` and `API_URL` is absent
- **THEN** generation fails with an error naming `API_URL`, the source, table,
  and field

#### Scenario: Default is used for an absent variable

- **WHEN** a TOML value is `$API_URL=https://default.example` and `API_URL` is
  absent
- **THEN** the generated field uses `https://default.example`

#### Scenario: Present empty value wins over default

- **WHEN** a TOML value is `$LABEL=fallback` and `LABEL` exists with an empty
  value
- **THEN** the generated field uses the empty environment value

#### Scenario: Default contains equals signs

- **WHEN** a TOML value is `$TOKEN=a=b=c` and `TOKEN` is absent
- **THEN** the fallback is the literal string `a=b=c`

### Requirement: Dollar escaping and reference boundaries

The generator SHALL interpret `$$` at the beginning of a TOML string as one
literal `$`, SHALL leave dollar signs elsewhere in a string literal, and SHALL
reject a single-dollar prefix that is not valid environment reference syntax.

#### Scenario: Escaped leading dollar

- **WHEN** a TOML value is `$$API_URL`
- **THEN** the generated value is the literal string `$API_URL` without an
  environment lookup

#### Scenario: Embedded dollar is literal

- **WHEN** a TOML value is `cost-$USD`
- **THEN** the generated value remains `cost-$USD`

#### Scenario: Malformed reference

- **WHEN** a TOML string begins with a single `$` but has no valid variable
  name or contains invalid reference syntax
- **THEN** generation fails with an error identifying the source, table, and
  field

### Requirement: Typed scalar conversion

After lookup or fallback selection, the generator SHALL convert the resolved
string to the constructor parameter's supported scalar type: unchanged text for
`String`, base-10 text for `int`, Dart floating-point text for `double`, and
exact lowercase `true` or `false` for `bool`.

#### Scenario: Numeric and boolean environment values

- **WHEN** environment references target `int`, `double`, or `bool` parameters
  and their resolved text is valid for those types
- **THEN** the generator emits type-compatible Dart constants

#### Scenario: Invalid typed value

- **WHEN** resolved environment text cannot be converted to the target type
- **THEN** generation fails with an error naming the variable, target type,
  source, table, and field without printing the environment value

### Requirement: Defaults are literal and non-recursive

The generator SHALL NOT interpret environment reference syntax inside the
fallback portion of another reference.

#### Scenario: Dollar-prefixed fallback

- **WHEN** a TOML value is `$PRIMARY=$SECOND`, `PRIMARY` is absent, and `SECOND`
  is present
- **THEN** the resolved value is the literal string `$SECOND`

### Requirement: Resolved values remain compile-time constants

Environment lookup SHALL occur only while generating code, and generated
registries SHALL contain resolved constant literals without a runtime
environment dependency.

#### Scenario: Runtime environment changes

- **WHEN** the process environment changes after generation
- **THEN** the generated registry retains the value selected during generation
