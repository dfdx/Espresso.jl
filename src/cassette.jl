## cassette.jl - building ExGraph using Cassette.jl

using Cassette
import Cassette: @context, @hook, @primitive, mapcall, Box, unbox


# mutable struct Counter
#     count::Int
# end


# Cassette.@context CountCtx


# # Cassette.@hook CountCtx c::Counter function f(arg::T) where {T}
# #     println("$(c.count) due to $(f)")
# #     c.count += 1
# # end


# c = Counter(0)


# @hook CountCtx c::Counter function (::typeof(log))(x::Number)
#     println("calling log, counter is $(c.count)")
#     c.count += 1
# end


# @hook CountCtx c::Counter function (::typeof(exp))(x::Number)
#     println("calling exp, counter is $(c.count)")
#     c.count += 1
# end


# f(x) = exp(log(exp(x)))

# Cassette.overdub(CountCtx, f, metadata = c)(108)


@context ExCtx

# @primitive ExCtx g::ExGraph (::typeof(sin))(x) = (println("sin"); sin(x))

@primitive ctx::ExCtx g::ExGraph sin(x) = begin
    println("sin");
    println(g)
    println(mapcall(x -> unbox(ctx, x), sin, x))
    
    sin(x)

end

# @primitive ExCtx g::ExGraph fn(x) = (println("this is $fn"); fn(x))


fun(x::Float64) = sin(x) + 1


function _main()
    g = ExGraph()

    ctx = ExCtx(6250862297977572493)
    Cassette.overdub(ExCtx, fun, metadata = g)(Box(ctx, 108))
end
