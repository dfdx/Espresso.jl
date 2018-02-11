
## tracked.jl - build ExGraph using tracked data types

import Base: +, -, *, /, log, exp, min, max, reshape, transpose, sum, mean,
    minimum, maximum


const DEFAULT_GRAPH = Ref(ExGraph())

get_default_graph() = DEFAULT_GRAPH[]
set_default_graph(g::ExGraph) = (DEFAULT_GRAPH[] = g)
reset_default_graph() = (DEFAULT_GRAPH[] = ExGraph())


## TRACKED REAL

struct TrackedReal <: Real
    graph::ExGraph
    var::Symbol
    val::Real
end

TrackedReal(var::Symbol, val::Real) = TrackedReal(get_default_graph(), var, val)
Base.show(io::IO, x::TrackedReal) = print(io, "Tracked($(x.var) = $(x.val))")
tracked_val(g::ExGraph, var::Symbol, val::Real) = TrackedReal(g, var, val)

struct TrackedArray{T,N} <: AbstractArray{T,N}
    graph::ExGraph
    var::Symbol
    val::AbstractArray{T,N}
end

TrackedArray(var::Symbol, val::AbstractArray) = TrackedArray(get_default_graph(), var, val)

Base.show(io::IO, x::TrackedArray{T,N}) where {T,N} =
    print(io, "Tracked{$T,$N}($(x.var) = $(x.val))")

tracked_val(g::ExGraph, var::Symbol, val::AbstractArray) = TrackedArray(g, var, val)

## conversion and promotion


tracked(g::ExGraph, x::TrackedReal) = x
tracked(g::ExGraph, x::TrackedArray) = x

function tracked(g::ExGraph, x::T) where {T <: Real}
    var = genname()
    push!(g, ExNode{:constant}(var, x; val=x))
    return TrackedReal(g, var, x)
end

function tracked(g::ExGraph, x::T) where {T <: AbstractArray}
    var = genname()
    push!(g, ExNode{:constant}(var, x; val=x))
    return TrackedArray(g, var, x)
end


value(x::TrackedArray) = x.v
value(x::TrackedReal) = x.v
value(x) = x

istracked(x::TrackedReal) = true
istracked(x::TrackedArray) = true
istracked(::Type{T}) where T = (T <: TrackedReal || T <: TrackedArray)
istracked(x) = false


Base.promote_rule(::Type{TrackedReal}, ::Type{<:Real}) = TrackedReal

function Base.convert(::Type{TrackedReal}, x::R) where {R <: Real}
    var = genname()
    g = get_default_graph()
    push!(g, ExNode{:constant}(var, x; val=x))
    return TrackedReal(g, var, x)
end

Base.convert(::Type{TrackedReal}, x::TrackedReal) = x

## overloaded functions

# for op in (:+, :-, :*, :/, :^, :max, :min, :log, :exp)

#     @eval function $op(xs::TrackedReal...)
#         x1 = xs[1]
#         val = $op([x.val for x in xs]...)
#         tv = tracked_val(x1.graph, genname(), val)
#         iop = Symbol($op)
#         ex = Expr(:call, iop, [x.var for x in xs]...)
#         nd = ExNode{:call}(tv.var, ex; val=val)
#         push!(x1.graph, nd)
#         return tv
#     end

# end


# for op in (:+, :-, :*, :/, :^, :max, :min)

#     @eval function $op(x::TrackedReal, y::TrackedReal)
#         val = $op(x.val, y.val)
#         tv = tracked_val(x.graph, genname(), val)
#         iop = Symbol($op)
#         ex = :($iop($(x.var), $(y.var)))
#         nd = ExNode{:call}(tv.var, ex; val=val)
#         push!(x.graph, nd)
#         return tv
#     end

# end



## TRACKED ARRAY


# TODO: should write this to graph? presumably no
Base.size(x::TrackedArray) = size(x.val)
# TODO: and these? presumably yes, but be carefull about printing
Base.getindex(x::TrackedArray, I...) = getindex(x.val, I...)
Base.setindex!(x::TrackedArray, val, I...) = setindex!(x.val, val, I...)


## conversion and promotion

Base.promote_rule(::Type{TrackedArray}, ::Type{<:AbstractArray}) = TrackedArray

function Base.convert(::Type{TrackedArray}, x::A) where {A <: AbstractArray}
    var = genname()
    g = get_default_graph()
    push!(g, ExNode{:constant}(var, x; val=x))
    return TrackedArray(g, var, x)
end

Base.convert(::Type{TrackedArray}, x::TrackedArray) = x

# overloaded functions

# for op in (:+, :-, :*, :/, :^, :transpose, :sum, :mean, :minimum, :maximum)

#     @eval function $op(xs::TrackedArray...)
#         x1 = xs[1]
#         val = $op([x.val for x in xs]...)
#         tv = tracked_val(x1.graph, genname(), val)
#         iop = Symbol($op)
#         ex = Expr(:call, iop, [x.var for x in xs]...)
#         nd = ExNode{:call}(tv.var, ex; val=val)
#         push!(x1.graph, nd)
#         return tv
#     end

# end





function track_call(sig)
    @assert sig.head == :call
    op = sig.args[1]
    vars_types, kw = split_params(sig)
    call_ex = nothing; ex_in_ex = nothing
    if isempty(kw)
        call_ex = Expr(:call, op,
                       [istracked(eval(t)) ? :($(v).val) : v for (v, t) in vars_types]...)
        ex_in_ex = Expr(:call, :Expr, QuoteNode(:call), QuoteNode(op),
                        [istracked(eval(t)) ? Expr(:., sig_var, QuoteNode(:var)) : sig_var
                         for (sig_var, t) in vars_types]...)
    else        
        call_ex = Expr(:call, op, make_kw_params(kw),
                       [istracked(eval(t)) ? :($(v).val) : v for (v, t) in vars_types]...)
        keys = [k for (k, v) in kw]

        # we need to get this:
        # :( Expr(:call, :mult, Expr(:parameters, Expr(:kw, :pow, pow)), :(x.var)) )
        # TODO: no, this way we pass fixed paramerers instead of passed values - done!
        ex_in_ex = Expr(:call, :Expr, QuoteNode(:call), QuoteNode(op),
                        Expr(:call, :Expr, QuoteNode(:parameters),
                             [Expr(:call, :Expr, QuoteNode(:kw), QuoteNode(k), k)
                             for k in keys]...),
                        [istracked(eval(t)) ? Expr(:., sig_var, QuoteNode(:var)) : sig_var
                         for (sig_var, t) in vars_types]...)
    end

    defquot = quote
        function $op($(sig.args[2:end]...))
            val = $call_ex
            tv = tracked_val(x.graph, genname(), val) # TODO: x may be undefined
            ex = $ex_in_ex
            nd = ExNode{:call}(tv.var, ex; val=val)
            push!(x.graph, nd)
            return tv
        end
    end
    return defquot.args[2]
end


function track_bcast(sig)
    @assert sig.head == :.
    op = sig.args[1]
    sig_vars, types = unzip([(arg.args[1], eval(arg.args[2])) for arg in sig.args[2].args])
    bcast_ex = Expr(:., op, Expr(:tuple, [istracked(t) ? :($(v).val) : v
                                          for (v, t) in zip(sig_vars, types)]...))
    # we want to get this after code generation:
    # ex = :(Expr(:., :sin, Expr(:tuple, x.var, y.var)))
    ex_in_ex = Expr(:call, :Expr, QuoteNode(:.), QuoteNode(:sin),
                    Expr(:call, :Expr, QuoteNode(:tuple),
                         [Expr(:., sig_var, QuoteNode(:var)) for sig_var in sig_vars]...))
    defquot = quote
        function broadcast_(::typeof($op), $(sig.args[2].args...))
            val = $bcast_ex
            tv = tracked_val(x.graph, genname(), val) # TODO: x may be undefined
            ex = $ex_in_ex
            # println(ex)
            nd = ExNode{:bcast}(tv.var, ex; val=val)
            push!(x.graph, nd)
            return tv
        end
    end
    return defquot.args[2]
end



macro tracked(sig)
    if sig.head == :call
        return track_call(sig)
    elseif sig.head == :.
        return track_bcast(sig)
    else
        error("Can only track calls or broadcasting")
    end
end


@tracked +(x::TrackedReal, y::TrackedReal)
@tracked -(x::TrackedReal, y::TrackedReal)
@tracked *(x::TrackedReal, y::TrackedReal)
@tracked /(x::TrackedReal, y::TrackedReal)

@tracked *(x::TrackedArray, y::TrackedArray)
@tracked maximum(x::TrackedArray)

@tracked reshape(x::TrackedArray, dims::Tuple{Int})
@tracked reshape(x::TrackedArray, dims::Tuple{Int, Int})
@tracked reshape(x::TrackedArray, dims::Tuple{Int, Int, Int})
@tracked reshape(x::TrackedArray, dims::Tuple{Int, Int, Int, Int})
@tracked reshape(x::TrackedArray, dims::Tuple{Int, Int, Int, Int, Int})
@tracked reshape(x::TrackedArray, dims::Tuple{Int, Int, Int, Int, Int, Int})

@tracked sin.(x::TrackedArray)
@tracked cos.(x::TrackedArray)



## why this one doesn't work?
# for (op, dotop) in [(+, .+), (-, .-), (*, .*), (/, ./)]
#     @eval function broadcast_(::typeof($op), x::TrackedArray, y::TrackedArray)
#         val = $dotop(x.val, y.val)
#         var = genname()
#         nd = ExNode{:call}(var, :($(x.var) $dotop $(y.var)))
#         push!(x.graph, nd)
#         return TrackedArray(var, val)
#     end
# end



# I couldn't find a way to overload .+ and friends as either call or broadcasting
# fortunately, the list of such unusual operations is small and fixed
function broadcast_(::typeof(+), x::TrackedArray, y::TrackedArray)
    val = x.val .+ y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) .+ $(y.var)))
    push!(x.graph, nd)
    return TrackedArray(var, val)
end
function broadcast_(::typeof(-), x::TrackedArray, y::TrackedArray)
    val = x.val .- y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) .- $(y.var)))
    push!(x.graph, nd)
    return TrackedArray(var, val)
end
function broadcast_(::typeof(*), x::TrackedArray, y::TrackedArray)
    val = x.val .* y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) .* $(y.var)))
    push!(x.graph, nd)
    return TrackedArray(var, val)
end
function broadcast_(::typeof(/), x::TrackedArray, y::TrackedArray)
    val = x.val ./ y.val
    var = genname()
    nd = ExNode{:call}(var, :($(x.var) ./ $(y.var)))
    push!(x.graph, nd)
    return TrackedArray(var, val)
end



# tests


mult(x::Array; pow=2, bias=1) = x .^ pow .+ bias

@tracked mult(x::TrackedArray; pow=2, bias=1)



function main()
    g = reset_default_graph()
    a = TrackedReal(:a, 1.0)
    b = TrackedReal(:b, 2.0)
    c = a * b + a
    println(g)

    g = reset_default_graph()
    A = TrackedArray(g, :A, rand(3,4))
    B = TrackedArray(g, :B, rand(4,3))
    C = A * B
    println(g)


    sin.(A)


    sig = :(conv2d(x::TrackedArray, w::TrackedArray; stride=1))
end
