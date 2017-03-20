
## expand_temp.jl - expand temporary variables in ExGraph
##
## This is an outdated version of expand_deps, remains here
## for compatibility with XDiff.jl only

expand_temp(g::ExGraph, nd::ExNode{:input}) = variable(nd)
expand_temp(g::ExGraph, nd::ExNode{:constant}) = value(nd)
expand_temp(g::ExGraph, nd::ExNode{:(=)}) = expand_temp(g, expr(nd))

function expand_temp(g::ExGraph, nd::ExNode{:call})
    deps = dependencies(nd)
    expanded = Dict([(x, expand_temp(g, g[x])) for x in deps])
    return subs(expr(nd), expanded)
end

function expand_temp(g::ExGraph, nd::ExNode{:bcast})
    deps = dependencies(nd)
    expanded = Dict([(x, expand_temp(g, g[x])) for x in deps])
    return subs(expr(nd), expanded)
end

function expand_temp(g::ExGraph, x::Symbol)
    if haskey(g.idx, x)
        return expand_temp(g, g[x])
    else
        return x
    end
end

function expand_temp(g::ExGraph, ex::Expr)
    new_args = [expand_temp(g, arg) for arg in ex.args]
    return Expr(ex.head, new_args...)
end

expand_temp(g::ExGraph, x) = x

