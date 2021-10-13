"""
    get_query_args_str(args::AbstractDict)

Get the mutation arguments string and a dictionary containing the argument names, which will
not necessarily match the name of the types in the schema.

Uses an internal function to go through `args` dictionary, recursing down through the values
that are  `AbstractDict` or `Vector{<:AbstractDict}`, ensuring that no argument name is
duplicated and enumerating multiple of the same type if in a vector.

# Examples
```jldoctest; setup=:(using GraphQLClient: get_query_args_str, prettify_query)
julia> args = Dict("TopLevelVarA" => "value", "TopLevelVarB" => 2);

julia> str, arg_names = get_query_args_str(args);

julia> println(prettify_query(str))
(
    TopLevelVarA:\$TopLevelVarA
    TopLevelVarB:\$TopLevelVarB
)

julia> args = Dict("A" => "value", "B" => 2, "C" => Dict("D" => 3, "E" => 4));

julia> str, arg_names = get_query_args_str(args);

julia> print(prettify_query(str))
(
    B:\$B
    A:\$A
    C:{
        D:\$D
        E:\$E
    }
)

julia> args = Dict("A" => "value", "B" => 2, "C" => [Dict("D" => 3, "E" => 4), Dict("D" => 5, "E" => 6), Dict("D" => 7, "E" => 8)]);

julia> str, arg_names = get_query_args_str(args);

julia> print(prettify_query(str))
(
    B:\$B
    A:\$A
    C:[
        {
            D:\$D1
            E:\$E1
        }
        {
            D:\$D2
            E:\$E2
        }
        {
            D:\$D3
            E:\$E3
        }
    ]
)
```
"""
function get_query_args_str(args::AbstractDict)
    arg_names = initialise_arg_names(args)
    fieldname_tracker = String[] # Used by internal function

    function recursive_get(arg_values::AbstractDict, arg_names::AbstractDict, enumerate)
        str = ""
        for (fieldname, val) in arg_values
            if isa(val, AbstractDict)
                # Wrap in fieldname:{} and go into next dictionary level
                str *= "$fieldname:{" * recursive_get(val, arg_names[fieldname], enumerate) * "},"
            elseif isa(val, AbstractVector{<:AbstractDict})
                # Wrap in fieldname:[] and to into each element (dictionary) of vector, enumerating argument names
                str *= "$fieldname:[" 
                for i in eachindex(val)
                    str *= "{" * recursive_get(val[i], arg_names[fieldname][i], enumerate+=1) * "},"
                end
                str *= "],"
            else
                name = fieldname
                str *= "$fieldname:\$$fieldname"
                if is_field_name_used(name, fieldname_tracker)
                    enumerate += 1
                end
                if enumerate > 0
                    name = fieldname * "__" * string(enumerate)
                    str *= string(enumerate)
                end

                # Add to tracker
                push!(fieldname_tracker, name)
                arg_names[fieldname] = name
                str *= ","
            end
        end
        return str
    end
    query_args_str = "(" * recursive_get(args, arg_names, 0) * ")"
    return query_args_str, arg_names
end

"""
    is_field_name_used(fieldname, fieldnamelist)

True if `fieldname` is in `fieldnamelist`.
"""
is_field_name_used(fieldname, fieldnamelist) = fieldname in fieldnamelist

"""
    initialise_arg_names(args::Dict)

Recursively create `arg_names` Dict with same structure (dictionaries and vectors) and keys
as `args`. Values are initialised as empty strings.

# Examples
```jldoctest; setup=:(using GraphQLClient: initialise_arg_names)
julia> args = Dict("int" => 1, "vector" => [1, 2, 3], "dict" => Dict("float" => 1.0), "vec_dict" => [Dict("bool" => true)])
Dict{String, Any} with 4 entries:
  "int"      => 1
  "dict"     => Dict("float"=>1.0)
  "vec_dict" => Dict{String, Bool}[Dict("bool"=>1)]
  "vector"   => [1, 2, 3]

julia> arg_names = initialise_arg_names(args)
Dict{String, Any} with 4 entries:
  "int"      => ""
  "dict"     => Dict{String, Any}("float"=>"")
  "vec_dict" => Dict{String, Any}[Dict("bool"=>"")]
  "vector"   => ""
```
"""
initialise_arg_names(args::Dict) = _initialise_arg_names(args)
function _initialise_arg_names(args::Dict)
    arg_names = Dict{String, Any}()
    for (key, val) in args
        arg_names[key] = _initialise_arg_names(val)
    end
    return arg_names
end
_initialise_arg_names(val) = ""
_initialise_arg_names(val::AbstractVector{<:AbstractDict}) = _initialise_arg_names.(val)

"""
    directly_write_query_args(query_args)

Returns a string which represents `query_args` by inserting values directly into the string.
Strings are bracketed with \" as this is required by GraphQL, but unfortunately this does
not work for ENUMs as we cannot tell if a string is meant to be an enum or not without
introspection. Therefore, any enums must be wrapped by a `GQLEnum`.

# Examples
```jldoctest; setup=:(using GraphQLClient: directly_write_query_args, prettify_query)
julia> query_args = Dict("string"=>"my_string", "dict"=>Dict("bool"=>true,"int"=>1), "vec"=>[Dict("float"=>1.0)])
Dict{String, Any} with 3 entries:
  "dict"   => Dict{String, Integer}("int"=>1, "bool"=>true)
  "string" => "my_string"
  "vec"    => [Dict("float"=>1.0)]

julia> println(prettify_query(directly_write_query_args(query_args)))
dict:{
    int:1
    bool:true
}
string:"my_string"
vec:[
    {
        float:1.0
    }
]

julia> query_args = Dict("string"=>"my_string", "enum" => GQLEnum("my_enum"))
Dict{String, Any} with 2 entries:
  "string" => "my_string"
  "enum"   => GQLEnum("my_enum")

julia> println(prettify_query(directly_write_query_args(query_args)))
string:"my_string"
enum:my_enum
```
"""
function directly_write_query_args(query_args)
    str = ""
    for (key, val) in query_args
        str *= "$key:"
        str *= _get_val_str(val)
        str *= ","
    end
    return rstrip(str, ',')
end

"""
    _get_val_str(val::String)
    _get_val_str(val::Dict)
    _get_val_str(val::Vector)
    _get_val_str(enum::GQLEnum) 
    _get_val_str(val)

Return value string for `directly_write_query_args`
"""
_get_val_str(val::String) = "\"$val\""
_get_val_str(val::Dict) = "{" * directly_write_query_args(val) * "}"
_get_val_str(val::Vector) = "[" * join(_get_val_str.(val)) * "]" 
_get_val_str(enum::GQLEnum) = "$(enum.value)"
_get_val_str(val) = string(val)

"""
    prettify_query(str)

Prettifies a string, nesting for bracket types and adding new lines for commas.

# Examples
```jldoctest; setup=:(using GraphQLClient)
julia> println(GraphQLClient.prettify_query("[{(a)}]"))
[
    {
        (
            a
        )
    }
]
julia> println(GraphQLClient.prettify_query("[{(a,b),(c,d)}]"))
[
    {
        (
            a
            b
        )
        (
            c
            d
        )
    }
]
```
"""
function prettify_query(str)
    buf = IOBuffer() 
    indent = 0
    opening_chars = ('{', '(', '[')
    closing_chars = ('}', ')', ']')
    new_line_chars = ('}', ')', ']', ',')
    previous_char = 'a'
    for char in str
        # if !(char == ',') && (in(char, opening_chars) && in(previous_char, new_line_chars)) || in(previous_char, opening_chars)
        if !(char == ',') && (in(char, opening_chars) && previous_char == ',') || in(previous_char, opening_chars)
            write(buf, repeat(" ", indent))
        end
        if char in opening_chars
            write(buf, "$char\n")
            indent += 4
        elseif char in closing_chars
            previous_char != ',' && write(buf, "\n")
            indent -= 4
            write(buf, repeat(" ", indent))
            write(buf, char)
        elseif char == ','
            write(buf, "\n")
        else
            in(previous_char, new_line_chars) && write(buf, repeat(" ", indent))
            write(buf, char)
        end
        previous_char = char
    end
    String(take!(buf))
end