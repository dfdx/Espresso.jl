
## tracked.jl - build ExGraph using tracked data types

import Base: +, -, *, /, log, exp, min, max, reshape, transpose, sum, mean,
    abs, abs2, >, >=, <, <=, minimum, maximum, getindex
# import Broadcast: broadcasted


const DEFAULT_GRAPH = Ref(ExGraph())

get_default_graph() = DEFAULT_GRAPH[]
set_default_graph(g::ExGraph) = (DEFAULT_GRAPH[] = g)
reset_default_graph!() = (DEFAULT_GRAPH[] = ExGraph())
swap_default_graph!(g::ExGraph) = (og = DEFAULT_GRAPH[]; DEFAULT_GRAPH[] = g; og)


# @tracking macro

function track_call(sig)
    @assert sig.head == :call
    op = sig.args[1]
    vars_types, kw = split_params(sig)
    call_ex = nothing; ex_in_ex = nothing
    if isempty(kw)
        call_ex = Expr(:call, op,
                       [istracked(Core.eval(@__MODULE__, t)) ? :($(v).val) : v
                        for (v, t) in vars_types]...)
        ex_in_ex = Expr(:call, :Expr, QuoteNode(:call), QuoteNode(op),
                        [(istracked(Core.eval(@__MODULE__, t)) ? Expr(:., sig_var, QuoteNode(:var))
                         : sig_var) for (sig_var, t) in vars_types]...)
    else
        call_ex = Expr(:call, op, make_kw_params(kw),
                       [istracked(Core.eval(@__MODULE__, t)) ? :($(v).val) : v
                        for (v, t) in vars_types]...)
        keys = [k for (k, v) in kw]
        # we need to get this:
        # :( Expr(:call, :mult, Expr(:parameters, Expr(:kw, :pow, pow)), :(x.var)) )
        ex_in_ex = Expr(:call, :Expr, QuoteNode(:call), QuoteNode(op),
                        Expr(:call, :Expr, QuoteNode(:parameters),
                             [Expr(:call, :Expr, QuoteNode(:kw), QuoteNode(k), k)
                             for k in keys]...),
                        [(istracked(Core.eval(@__MODULE__, t)) ? Expr(:., sig_var, QuoteNode(:var))
                          : sig_var) for (sig_var, t) in vars_types]...)
    end
    defquot = quote
        function $op($(sig.args[2:end]...))
            val = $call_ex
            tv = tracked(x.graph, genname(), val) # TODO: x may be undefined
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
    sig_vars, types = unzip([(arg.args[1], Core.eval(@__MODULE__, arg.args[2]))
                             for arg in sig.args[2].args])
    bcast_ex = Expr(:., op, Expr(:tuple, [istracked(t) ? :($(v).val) : v
                                          for (v, t) in zip(sig_vars, types)]...))
    # we want to get this after code generation:
    # ex = :(Expr(:., :sin, Expr(:tuple, x.var, y.var)))
    ex_in_ex = Expr(:call, :Expr, QuoteNode(:.), QuoteNode(op),
                    Expr(:call, :Expr, QuoteNode(:tuple),
                         [istracked(t) ? Expr(:., sv, QuoteNode(:var)) : QuoteNode(:var)
                          for (sv, t) in zip(sig_vars, types)]...))
    defquot = quote
        function Broadcast.broadcasted(::typeof($op), $(sig.args[2].args...))
            val = $bcast_ex
            tv = tracked(x.graph, genname(), val) # TODO: x may be undefined
            ex = $ex_in_ex
            # println(ex)
            nd = ExNode{:bcast}(tv.var, ex; val=val)
            push!(x.graph, nd)
            return tv
        end
    end
    return defquot.args[2]
end


"""
Define a function or broadcasting rule for the specified signature which computes
the result as for ordinary (not tracked) data and writes it to the graph.

Note: this function expects at least 1 parameter of TReal or TArray type
with name `x`.
"""
macro tracking(sig)
    if sig.head == :call
        return track_call(sig)
    elseif sig.head == :.
        # TODO: we also need to add the op to broadcast list in `unfuse.jl`
        return track_bcast(sig)
    else
        error("Can only track calls or broadcasting")
    end
end


# TODO: also track dot ops with scalars, e.g. x .+ 1


## utils

function tracked_exgraph(f::Function, args...)
    ctx = Dict{Any,Any}(:method => :track)
    input_vars = [genname() for i=1:length(args)]
    inputs = [iv => a for (iv, a) in zip(input_vars, args)]
    g = ExGraph(; ctx=ctx, inputs...)
    # replace default graph to capture constants to `g` as well
    og = swap_default_graph!(g)
    tr_args = [tracked(g, var, val) for (var, val) in inputs]
    # evaluate function with tracked args
    f(tr_args...)
    # put original graph back
    swap_default_graph!(og)
    return g
end
