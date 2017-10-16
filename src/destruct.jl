
## destruct.jl - deconstruction of structs
##
## TODO: now Espresso supports structures natively, remove this?

"Check if an object is of a struct type, i.e. not a number or array"
isstruct(::Type{T}) where T = !isbits(T) && !(T <: AbstractArray)
isstruct(obj) = !isbits(obj) && !isa(obj, AbstractArray)

field_values(m) = [getfield(m, f) for f in fieldnames(typeof(m))]
named_field_values(m) = [f => getfield(m, f) for f in fieldnames(typeof(m))]


"""
Replace all struct arguments by a list of their plain analogues.
Example:

    args = [:m, :x, :y]
    types = (Linear, Matrix{Float64}, Matrix{Float64})
    ex = :(sum((m.W * x .+ m.b) - y))

    destruct(args, types, ex)
    # ==>
    # ([:m_W, :m_b, :x, :y],
    #  :(sum((m_W * x .+ m_b) - y)),
    #  Dict(:(m.W) => :m_W, :(m.b) => :m_b))
"""
function destruct(args::Vector{Symbol}, types, ex)
    st = Dict()
    new_args = Symbol[]
    for (arg, T) in zip(args, types)
        if isstruct(T)
            for f in fieldnames(T)
                new_arg = Symbol("$(arg)_$(f)")
                push!(new_args, new_arg)
                f_ex = Expr(:., arg, QuoteNode(f))
                st[f_ex] = new_arg
            end
        else
            push!(new_args, arg)
        end
    end
    return new_args, subs(ex, st), st
end


function destruct_inputs(inputs)
    new_inputs = []
    for (k, v) in inputs
        if isstruct(v)
            for f in fieldnames(v)
                new_arg = Symbol("$(k)_$(f)")
                new_val = getfield(v, f)
                push!(new_inputs, new_arg => new_val)
            end
        else
            push!(new_inputs, k => v)
        end
    end
    return new_inputs
end
