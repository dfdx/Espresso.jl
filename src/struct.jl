
# struct.jl - utils for working with Julia structures
#
# Composite types, except for arrays, are not supported by core Espresso functions.
# However we can provide a set of wrapper and utility functions to make working
# with structs more pleasant

"Check if an object is of a struct type, i.e. not a number or array"
isstruct(::Type{T}) where T = !isbits(T) && !(T <: AbstractArray)
isstruct(obj) = !isbits(obj) && !isa(obj, AbstractArray)

field_values(m) = [getfield(m, f) for f in fieldnames(m)]
named_field_values(m) = [f => getfield(m, f) for f in fieldnames(m)]



function make_kw_params(kw_args)
    kw_params = [Expr(:kw, arg...) for arg in kw_args]
    return Expr(:parameters, kw_params...)
end


function make_func_expr(name, args, kw_args, body)
    ex = :(function name() end) |> sanitize
    # set name
    ex.args[1].args[1] = name
    # set kw arguments
    if !isempty(kw_args)
        push!(ex.args[1].args, make_kw_params(kw_args))
    end
    # set arguments
    push!(ex.args[1].args, args...)
    if isa(body, Expr) && body.head == :block
        push!(ex.args[2].args, body.args...)
    else
        push!(ex.args[2].args, body)
    end
    return ex
end
