# Private

```@contents
Pages = ["private.md"]
```

Package internals documentation.

## Client

```@autodocs
Modules = [GraphQLClient]
Pages = ["client.jl", "introspection.jl"]
Public = false
```

## Operations

```@autodocs
Modules = [GraphQLClient]
Pages   = ["queries.jl", "mutations.jl", "subscriptions.jl", "http_execution.jl", "gqlresponse.jl", "types.jl"]
Filter = t -> !in(t, (GraphQLClient.execute, GraphQLClient.GQLResponse))
Public = false
```

## Output Fields

```@autodocs
Modules = [GraphQLClient]
Pages   = ["output_fields.jl"]
Public = false
```

## Arguments

```@autodocs
Modules = [GraphQLClient]
Pages   = ["args.jl"]
Public = false
```

## Variables

```@autodocs
Modules = [GraphQLClient]
Pages   = ["variables.jl"]
Public = false
```

## Schema Utilities

```@autodocs
Modules = [GraphQLClient]
Pages   = ["schema_utils.jl"]
Public = false
```

## Type Introspection

```@autodocs
Modules = [GraphQLClient]
Pages   = ["type_construction.jl"]
Filter = t -> !in(t, (GraphQLClient.AbstractIntrospectedStruct,))
Public = false
```

## Logging

```@autodocs
Modules = [GraphQLClient]
Pages   = ["logging.jl"]
Public = false
```