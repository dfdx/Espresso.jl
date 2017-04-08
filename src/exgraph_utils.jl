
function expand_const_1(g::ExGraph, nd::Union{ExNode{:call}, ExNode{:bcast}})
    st = Dict()
    for dep in dependencies(nd)
        if haskey(g, dep) && isa(g[dep], ExNode{:constant})
            st[dep] = g[dep].val
        end
    end
    return subs(to_expr(nd), st)
end


# expand_temp(g::ExGraph, nd::ExNode{:input}) = variable(nd)
# expand_temp(g::ExGraph, nd::ExNode{:constant}) = value(nd)
# expand_temp(g::ExGraph, nd::ExNode{:(=)}) = expand_temp(g, expr(nd))

# function expand_temp(g::ExGraph, nd::ExNode{:call})
#     deps = dependencies(nd)
#     expanded = Dict([(x, expand_temp(g, g[x])) for x in deps])
#     return subs(expr(nd), expanded)
# end

# function expand_temp(g::ExGraph, nd::ExNode{:bcast})
#     deps = dependencies(nd)
#     expanded = Dict([(x, expand_temp(g, g[x])) for x in deps])
#     return subs(expr(nd), expanded)
# end

# function expand_temp(g::ExGraph, x::Symbol)
#     if haskey(g.idx, x)
#         return expand_temp(g, g[x])
#     else
#         return x
#     end
# end

# function expand_temp(g::ExGraph, ex::Expr)
#     new_args = [expand_temp(g, arg) for arg in ex.args]
#     return Expr(ex.head, new_args...)
# end

# expand_temp(g::ExGraph, x) = x


# iexpand_temp




iexpand_temp(g::ExGraph, nd::ExNode{:input}) = quote end
iexpand_temp(g::ExGraph, nd::ExNode{:constant}) = to_iexpr(nd)
iexpand_temp(g::ExGraph, nd::ExNode{:(=)}) =
    to_block(iexpand_temp(g, dependencies(nd)[1]), to_iexpr(nd))

function iexpand_temp(g::ExGraph, nd::ExNode{:call})
    deps = dependencies(nd)
    expanded = [iexpand_temp(g, g[x]) for x in deps]
    this_ex = to_iexpr(nd)
    return to_block(expanded..., this_ex)
end

function iexpand_temp(g::ExGraph, x::Symbol)
    if haskey(g.idx, x)
        return iexpand_temp(g, g[x])
    else
        return x
    end
end

function iexpand_temp(g::ExGraph, ex::Expr)
    new_args = [expand_temp(g, arg) for arg in ex.args]
    return to_block(new_args...)
end

iexpand_temp(g::ExGraph, x) = x


# dep vars

dep_vars!(g::ExGraph, nd::ExNode{:input}, result::Set{Symbol}) = begin end
dep_vars!(g::ExGraph, nd::ExNode{:constant}, result::Set{Symbol}) = begin end

function dep_vars!(g::ExGraph, nd::ExNode{:(=)}, result::Set{Symbol})
    dep = dependencies(nd)[1]
    push!(result, dep)
    dep_vars!(g, dep, result)
end

function dep_vars!(g::ExGraph, nd::ExNode{:call}, result::Set{Symbol})
    for dep in dependencies(nd)
        push!(result, dep)
        dep_vars!(g, dep, result)
    end
end

function dep_vars!(g::ExGraph, var::Symbol, result::Set{Symbol})
    push!(result, var)
    if haskey(g, var)
        dep_vars!(g, g[var], result)
    end
end

"""Recursively collect all variables that this one depends on"""
function dep_vars(g::ExGraph, var::Symbol)
    result = Set{Symbol}()
    dep_vars!(g, var, result)
    return result
end

function dep_vars!(g::ExGraph, ex::Expr, result::Set{Symbol})
    if ex.head == :call
        for arg in ex.args[2:end]
            dep_vars!(g, arg, result)
        end
    elseif ex.head == :ref
        dep_vars!(g, ex.args[1], result)
    end
end

dep_vars!(g::ExGraph, x, result) = begin end

function dep_vars(g::ExGraph, ex::Expr)
    result = Set{Symbol}()
    dep_vars!(g, ex, result)
    return result
end

dep_vars(g::ExGraph, x) = Set{Symbol}()


