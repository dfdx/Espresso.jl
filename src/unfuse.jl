## unfuse.jl - prevent broadcasting fusion for tracked data
##
## Based on AutoGrad.jl:
## https://github.com/denizyuret/AutoGrad.jl/blob/42616b245e28f52a5f5207ec65cc2fdce6a595a7/src/unfuse.jl

import Base.Broadcast: broadcast, broadcast_c, containertype


struct Broadcasted{T}
    value::T
end

getvalue(x::Broadcasted) = x.value

# We need this to not override regular broadcast(f, A, Bs...):
broadcast(f, x::Union{Number, AbstractArray}...) = broadcast_c(f, containertype(x...), x...)

# This captures cases where at least one arg is a TrackedArray:
# broadcast(f, x::Union{Number, AbstractArray, TrackedArray}...) = f(Broadcasted.(x)...).value
broadcast(f, x::Union{Number, AbstractArray, TrackedArray}...) = f(Broadcasted(x)...).value


# broadcast_func(f) gets called with every primitive function in AutoGrad.

function broadcast_func(f)
    f = Symbol(lstrip(string(f), '.'))
    bf = Symbol("broadcast!!", f)
    if !isdefined(bf) # !isdefined(Espresso, bf)
        @eval begin
            # We need this when x is of a regular type (@primitive only defines bf for Rec)
            $bf(x...) = (println("bf over regular type"); broadcast($f, x...))
            $f(x::Broadcasted...) = (println("f over Broadcasted, arg is $x");
                                     $bf(getvalue.(x)...) |> Broadcasted)
            
            # We need the following because sometimes the interpreter does not
            # convert all args to Broadcasted:
            # $f(x1::Broadcasted, x2) = $bf(getvalue(x1), x2) |> Broadcasted
            # $f(x1, x2::Broadcasted) = $bf(x1, getvalue(x2)) |> Broadcasted
        end
    end
    return bf
end

# TODO: overload broadcast!!func for tracked arrays


foo(x::Number) = 2x

broadcast_func(foo)

broadcast!!foo(x::TrackedArray) = (println("broadcast!!foo over TrackedArray, x.val = $(x.val)");
                                   foo.(x.val))


function main()
    g = reset_default_graph()
    a = TrackedReal(:a, 1.0)
    b = TrackedReal(:b, 2.0)
    c = a * b + a
    println(g)

    g = ExGraph()
    A  = TrackedArray(g, :A, rand(3,4))
    B  = TrackedArray(g, :B, rand(4,3))
    C = A * B
    println(g)
end
