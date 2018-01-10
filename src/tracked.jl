
## tracked.jl - build ExGraph using tracked data types

struct TrackedReal <: Real
    g::ExGraph    # graph
    n::Symbol     # name
    v::Real       # value
end


Base.show(io::IO, x::TrackedReal) = print(io, "Tracked($(x.n) = $(x.v))")

# TODO: define for TrackedArrays
tracked_val(g::ExGraph, n::Symbol, v::Real) = TrackedReal(g, n, v)


# function Base.:+(x::TrackedReal, y::TrackedReal)
#     v = x.v + y.v
#     tr = TrackedReal(x.g, genname(), v)
#     nd = ExNode{:call}(tr.n, :($(x.n) + $(y.n)); val=v)
#     push!(g, nd)
#     return tr
# end


# function Base.:*(x::TrackedReal, y::TrackedReal)
#     v = x.v * y.v
#     tv = tracked_val(x.g, genname(), v)
#     nd = ExNode{:call}(tv.n, :($(x.n) * $(y.n)); val=v)
#     push!(g, nd)
#     return tv
# end



# TODO: use promotion to convert Real to TrackedReal

function tracked(ex)
    @assert ex.head == :call
    op = ex.args[1]
    params, kw = parse_call_args(ex)
    vars, types = collect(zip([(p.args[1], p.args[2]) for p in params]...))
    call = Expr(:call, op, [:($var.v) for var in vars]...)    
    body = quote
        v = $(call)
        tv = tracked_val($(vars[1]).g, genname(), v)
        g_vars = [$(vari.n) for vari in $vars]
        stored_ex = Expr(:call, Symbol($op), g_vars...)
        nd = ExNode{:call}(tv.n, stored_ex; val=v)
        push!($(vars[1]).g, nd)
        return tv
    end
    return make_func_expr(op, params, kw, body)
end


macro tracked(ex)
    esc(tracked(ex))
end



import Base: +, -, *, /

@tracked *(x::TrackedReal, y::TrackedReal)
@tracked +(x::TrackedReal, y::TrackedReal)


function main()
    g = ExGraph()
    a = TrackedReal(g, :a, 1.0)
    b = TrackedReal(g, :b, 2.0)
    a * b
end
