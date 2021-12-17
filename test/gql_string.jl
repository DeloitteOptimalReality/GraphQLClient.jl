# Test escaping of $
@test "query(\$var:ID!){country(var:\$var){name}}" == gql"query($var:ID!){country(var:$var){name}}"

# Test turning off validation errors
str = @gql_str """
{countries{name}}
query{countries{name}}
""" false
@test_throws GraphQLParser.ValidationException GraphQLParser.is_valid_executable_document(str; throw_on_error=true)