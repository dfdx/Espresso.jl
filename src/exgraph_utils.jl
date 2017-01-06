
function expand_const_1(g::ExGraph, nd::ExNode{:call})
    st = Dict()
    for dep in dependencies(nd)
        if haskey(g, dep) && isa(g[dep], ExNode{:constant})
            st[dep] = g[dep].val
        end
    end
    return subs(to_expr(nd), st)
end


expand_temp(g::ExGraph, nd::ExNode{:input}) = variable(nd)
expand_temp(g::ExGraph, nd::ExNode{:constant}) = value(nd)
expand_temp(g::ExGraph, nd::ExNode{:(=)}) = expand_temp(g, expr(nd))

function expand_temp(g::ExGraph, nd::ExNode{:call})
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


# iexpand_temp


function to_block(exs...)
    new_exs = flatten([exprlike(ex) && ex.head == :block ? ex.args : [ex] for ex in exs])
    return sanitize(Expr(:block, new_exs...))
end

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


## propagate size

const SIZE_PROP_RULES =
    Dict((:*, [0, 0]) => :(()),
         (:*, [2, 1]) => :((_1[1])),
         (:*, [2, 2]) => :((_1[1], _2[2])))

function propagate_size!(g::ExGraph, nd::ExNode{:input})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    sizes[nd.var] = :(size($(nd.var)))
end

function propagate_size!(g::ExGraph, nd::ExNode{:constant})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    sz = size(nd.val)
    sizes[nd.var] = Expr(:tuple, sz...)
end

function propagate_size!(g::ExGraph, nd::ExNode{:(=)})
    dep = dependencies(nd)[1]
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    sizes[nd.var] = sizes[dep]
end


function graph_inputs(g::ExGraph)
    res = Dict()
    for nd in g.tape
        if isa(nd, ExNode{:input})
            res[nd.var] = nd.val
        end
    end
    return res
end

function ndims_from_size(g::ExGraph, var::Symbol)
    inputs = graph_inputs(g)
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    evex = subs(sizes[var], inputs)
    sz = eval(evex)
    return length(sz)
end

function propagate_size!(g::ExGraph, nd::ExNode{:call})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    deps = dependencies(nd)
    if in(:I, deps)
        lhs_idxs = nd.idxs[1]
        I_pos = findfirst(deps, :I)
        # I_idxs = nd.idxs[I_pos + 1]
        not_I_pos = 3 - I_pos
        not_I_idxs = nd.idxs[not_I_pos + 1]
        idxs_to_keep = findin(lhs_idxs, not_I_idxs)
        if isempty(idxs_to_keep)
            sizes[nd.var] = :(())
        else
            dep_size_expr = sizes[deps[not_I_pos]]
            size_expr = simplify(Expr(:ref, dep_size_expr, idxs_to_keep...))
            sizes[nd.var] = size_expr
        end
    elseif all(dep -> haskey(g, dep), deps)
        dep_dims = [ndims_from_size(g, dep) for dep in deps]
        sz_key = (expr(nd).args[1], dep_dims)
        if haskey(SIZE_PROP_RULES, sz_key)
            rpat = SIZE_PROP_RULES[sz_key]
            dep_sizes = [sizes[dep] for dep in deps]
            size_names = [Symbol("_$i") for i=1:length(deps)]
            st = Dict(zip(size_names, dep_sizes))
            size_ex = simplify(subs(rpat, st))
            sizes[nd.var] = size_ex
        else
            # TODO: take dep with max number of dims to handle broadcasting
            size_ex = sizes[deps[1]]
            sizes[nd.var] = size_ex
        end
    else
        error("Can't propagate size of $nd: not all deps present in graph")
    end

end


function propagate_size!(g::ExGraph)
    for nd in g.tape
        propagate_size!(g, nd)
    end
end
