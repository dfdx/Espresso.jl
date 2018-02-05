
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




# for op in (:reshape, )

#     @eval function $op(x::TrackedArray, dims::Int...)
#         val = $op(x.val, dims...)
#         tv = tracked_val(x.graph, genname(), val)
#         iop = Symbol($op)
#         ex = Expr(:call, iop, x.var, dims...)
#         nd = ExNode{:call}(tv.var, ex; val=val)
#         push!(x.graph, nd)
#         return tv
#     end

# end




function track_call(sig)
    @assert sig.head == :call
    op = sig.args[1]
    sig_vars, types = unzip([(arg.args[1], eval(arg.args[2])) for arg in sig.args[2:end]])
    call_ex = Expr(:call, op,
                [istracked(t) ? :($(v).val) : v for (v, t) in zip(sig_vars, types)]...)
    ex = Expr(:call, :Expr, QuoteNode(:call), QuoteNode(op),
              [Expr(:., sig_var, QuoteNode(:var)) for sig_var in sig_vars]...)

    defquot = quote
        function $op($(sig.args[2:end]...))
            val = $call_ex
            tv = tracked_val(x.graph, genname(), val) # TODO: x may be undefined
            ex = $ex
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
    # ex = Expr(:call, :Expr, QuoteNode(:.), QuoteNode(op),
    #           [Expr(:., sig_var, QuoteNode(:var)) for sig_var in sig_vars]...)
    # ex = Expr(:., :sin, Expr(:tuple, Expr(:., :A, QuoteNode(:val))))

    inner_exprs = [Expr(:call, :Expr, QuoteNode(:.), QuoteNode(sig_var),
                        Expr(:call, :QuoteNode, QuoteNode(:val))) for sig_var in sig_vars]
    ex_in_ex = Expr(:call, :Expr, QuoteNode(:.), QuoteNode(:sin),
                    Expr(:call, :Expr, QuoteNode(:tuple),
                         inner_exprs...))
    
    # ex_in_ex = Expr(:call, :Expr, QuoteNode(:.), QuoteNode(:sin),
    #                 Expr(:call, :Expr, QuoteNode(:tuple),
    #                      Expr(:call, :Expr, QuoteNode(:.), QuoteNode(:A),
    #                           Expr(:call, :QuoteNode, QuoteNode(:val)))))
    

    defquot = quote
        function broadcast_(::typeof($op), $(sig.args[2].args...))
            val = $bcast_ex
            tv = tracked_val(x.graph, genname(), val) # TODO: x may be undefined
            ex = $ex_in_ex
            println(ex)
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
@tracked maximum(x::TrackedArray)


@tracked sin.(x::TrackedArray)



# tests


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
end





function example(f_vars::Vector{Symbol})
    quote
        function foo($(f_vars...))
            ex_vars = [ :($v.name) for v in $f_vars ]
            Expr(:call, :op, ex_vars...)
        end
    end
end
