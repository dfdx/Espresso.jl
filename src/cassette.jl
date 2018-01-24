## cassette.jl - building ExGraph using Cassette.jl

using Cassette
import Cassette: @context, @hook


mutable struct Counter
    count::Int
end


Cassette.@context CountCtx


# Cassette.@hook CountCtx c::Counter function f(arg::T) where {T}
#     println("$(c.count) due to $(f)")
#     c.count += 1
# end


c = Counter(0)


@hook CountCtx c::Counter function (::typeof(log))(x::Number)
    println("calling log, counter is $(c.count)")
    c.count += 1
end


@hook CountCtx c::Counter function (::typeof(exp))(x::Number)
    println("calling exp, counter is $(c.count)")
    c.count += 1
end


f(x) = exp(log(exp(x)))

Cassette.overdub(CountCtx, f, metadata = c)(108)
