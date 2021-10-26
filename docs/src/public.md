# Public

```@contents
Pages = ["public.md"]
```

Documentation for GraphQLClient's public interface.

## Client

```@docs
Client
global_graphql_client
full_introspection!
get_queries
get_mutations
get_subscriptions
```

## Operations

```@docs
query
mutate
open_subscription
GraphQLClient.execute
GraphQLClient.GQLResponse
GraphQLClient.GQLEnum
GraphQLClient.Alias
```

## Type Introspection

```@docs
introspect_object
get_introspected_type
list_all_introspected_objects
initialise_introspected_struct
create_introspected_struct
GraphQLClient.AbstractIntrospectedStruct
```