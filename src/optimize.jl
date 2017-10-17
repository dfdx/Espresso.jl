
# optmizie.jl - optimize ExGraph

const OPT_PHS = [:X, :Y, :Z, :V, :W,
                 :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]

# const OPT_RULES = OrderedDict(
#     :(W[i,k,j] = X[i,k] .* Y[j,k]; Z[i,j] = W[i,k,j]) =>
#     :(genname__(1)[k,j] = Y[j,k]; Z[i,j] = X[i,k] * genname__(1)[k,j]),

#     :(W[i,k,j] = X[i,k] .* Y[k,j]; Z[i,j] = W[i,k,j]) =>
#     :(Z[i,j] = X[i,k] * Y[k,j]),

#     :(W[i,j,k] = X[i] .* Y[j,k]; Z[i,j] = W[i,j,k]) =>
#     :(Z[i,j] = X[i] .* Y[j,k]),

#     # :(W[j,k,i] = X[i] .* Y[j,k]; Z[i,j] = W[i,j,k]) =>
#     # :(Z[i,j] = X[i] .* Y[j,k]),

#     :(W[k,i,j] = X[k,i] .* Y[k,j]; Z[i,j] = W[k,i,j]) =>
#     :(genname__(1)[i,k] = X[k,i]; Z[i,j] = genname__(1)[i,k] * Y[k,j])
# )


const OPT_VEC_RULES = [
    :(Z = X * transpose(Y)) => :(Z = X * Y'),
    :(Z = X * Y') => :(Z = X * Y'),
    :(Z = transpose(X) * Y) => :(Z = X' * Y),
    :(Z = X' * Y) => :(Z = X' * Y),
]


function remove_unused(g::AbstractExGraph, outvars::Vector{Symbol})
    deps = collect_deps(g, outvars)
    push!(deps, outvars...)
    gr = reset_tape(g)
    for nd in g.tape
        if in(varname(nd), deps)
            push!(gr, nd)
        end
    end
    return gr
end


remove_unused(g::AbstractExGraph, outvar::Symbol) = remove_unused(g, [outvar])
remove_unused(g::AbstractExGraph) = remove_unused(g, [varname(g[end])])


"""
Removes unused variables from multiline expressions, e.g. in:

    x = u * v
    y = x + 1
    z = 2x

`y` isn't used to compute output variable `z`, so it's removed:

    x = u * v
    z = 2x

"""
function remove_unused(ex::Expr; output_vars=nothing)
    ex.head == :block || return ex  # nothing to remove
    g = ExGraph(ex; fuse=false)
    output_vars = output_vars != nothing ? output_vars : [varname(g[end])]
    deps = collect_deps(g, output_vars)
    for vname in output_vars
        push!(deps, vname)
    end
    res = quote end
    for subex in ex.args
        if subex.head == :(=)
            vname = split_indexed(subex.args[1])[1]
            if in(vname, deps)
                push!(res.args, subex)
            end
        else
            push!(res.args, subex)
        end
    end
    return res
end


function reset_tape(g::AbstractExGraph)
    new_g = deepcopy(g)
    new_g.tape = []
    new_g.idx = Dict()
    new_g.ctx = g.ctx  # experimental
    return new_g
end


function tryoptimize(ex::Expr)
    for (pat, subs_ex) in OPT_VEC_RULES
        new_ex_nlb = tryrewrite(ex, pat, subs_ex; phs=OPT_PHS, allow_ex=false)
        if !isnull(new_ex_nlb)
            new_ex = get(new_ex_nlb)
            genname_patterns = unique(findex(:(genname__(_n)), new_ex))
            if !isempty(genname_patterns)
                new_names = gennames(length(genname_patterns))
                st = Dict(zip(genname_patterns, new_names))
                return Nullable(subs(new_ex, st))
            else
                return Nullable(new_ex)
            end
        end
    end
    return Nullable{Expr}()
end


function expand_fixed_sequences(g::ExGraph, nd::ExNode)
    ex = to_expr(nd)
    changed = false
    for dep in dependencies(nd)
        expanded = subs(ex, Dict(dep => getexpr(g[dep])))
        new_ex = tryoptimize(expanded)
        if !isnull(new_ex)
            ex = get(new_ex)
            changed = true
        end
    end
    return changed ? copy(nd; category=:opaque, var=ex.args[1], ex=ex.args[2]) : nd
end


"""
Look at each node's dependencies and, if there are known pattern sequences,
rewrite them in a more optimal way.
"""
function expand_fixed_sequences(g::ExGraph)
    new_g = reset_tape(g)
    for nd in g.tape
        if isa(nd, ExNode{:input})
            push!(new_g, nd)
        else
            new_nd = expand_fixed_sequences(g, nd)
            push!(new_g, new_nd)
        end
    end
    new_g = remove_unused(new_g,  varname(new_g[end]))
    # new_g = fuse_assigned(new_g)
    return new_g
end


# common subexpression elimination

function eliminate_common(g::AbstractExGraph)
    g = reindex_from_beginning(g)
    new_g = reset_tape(g)
    existing = Dict()             # index of existing expressions
    st = Dict{Symbol,Symbol}()    # later var -> previous var with the same expression
    for nd in g.tape
        new_full_ex = subs(to_expr_kw(nd), st)
        vname, vidxs = split_indexed(new_full_ex.args[1])
        key = string((vidxs, new_full_ex.args[2]))
        if haskey(existing, key) &&
            (g[vname] |> getvalue |> size) == (g[existing[key]] |> getvalue |> size)
            st[vname] = existing[key]
        else
            # C = getcategory(nd)
            new_nd = copy(nd)
            setexpr_kw!(new_nd, new_full_ex.args[2])
            push!(new_g, new_nd)
            existing[key] = vname
        end
    end
    rename!(new_g, st)
    return new_g
end


# fuse broadcasting (EinGraph)

function is_bcast_indexed(nd::Union{ExNode{:call}, ExNode{:opaque}})
    all_idxs = get_indices(to_expr(nd); rec=true)
    lhs_idxs = isempty(all_idxs) ? [] : all_idxs[1]
    return all(idxs == lhs_idxs || isempty(idxs) for idxs in all_idxs)
end

is_bcast_indexed(nd::ExNode{:bcast}) = true
is_bcast_indexed(nd::ExNode) = false


function get_indices_in_expr(ex::Any, vname::Symbol)
    vars = get_vars(ex; rec=true)
    split_vars = [split_indexed(var) for var in vars]
    targets = [idxs for (x, idxs) in split_vars if x == vname]
    !isempty(targets) || error("Variable $vname doesn't occur in expression $ex")
    return targets[1]
end


function fuse_broadcasting_node(g::EinGraph, new_g::EinGraph, nd::ExNode)
    dep_nds = [new_g[dep] for dep in dependencies(nd)]
    if any(is_bcast_indexed(dep_nd) for dep_nd in dep_nds)
        # at least one dependency is broadcasting
        # transform node to :opaque and expand dep expression
        st = Dict{Any, Any}()
        for dep_nd in dep_nds
            if is_bcast_indexed(dep_nd)
                # if dependency is broadcasting, replace its name with its expression
                dep_ex = getexpr(dep_nd)
                idx_st = Dict(zip(varidxs(dep_nd),
                                  get_indices_in_expr(getexpr(nd), varname(dep_nd))))
                new_dep_ex = subs(dep_ex, idx_st)
                new_dep_ex = dep_ex
                st[getvar(dep_nd)] = new_dep_ex
            end
        end
        new_ex = subs(getexpr(nd), st)
        return copy(nd; ex=new_ex, category=:opaque)
    else
        return nd
    end
end


function fuse_broadcasting(g::EinGraph)
    new_g = reset_tape(g)
    for nd in g.tape
        if is_bcast_indexed(nd)
            push!(new_g, fuse_broadcasting_node(g, new_g, nd))
        else
            push!(new_g, nd)
        end
    end
    return remove_unused(new_g, varname(g[end]))
end


# fuse broadcasting (ExGraph)

function is_bcast_vec(nd::ExNode{:opaque})
    # convert to expression, re-parse and check every node
    return all(is_bcast_vec(nd) for nd in ExGraph(to_expr(nd)).tape)
end

const OLD_BCAST_OPS = Set([:.+, :.-, :.*, :./, :.^])

is_bcast_vec(nd::ExNode{:call}) = getexpr(nd).args[1] in OLD_BCAST_OPS
is_bcast_vec(nd::ExNode{:bcast}) = true
is_bcast_vec(nd::ExNode) = false


function fuse_broadcasting_node(g::ExGraph, new_g::ExGraph, nd::ExNode)
    dep_nds = [new_g[dep] for dep in dependencies(nd)]
    if any(is_bcast_vec(dep_nd) for dep_nd in dep_nds)
        # at least one dependency is broadcasting
        # transform node to :opaque and expand dep expression
        st = Dict{Any, Any}()
        for dep_nd in dep_nds
            if is_bcast_vec(dep_nd)
                # if dependency is broadcasting, replace its name with its expression
                dep_ex = getexpr(dep_nd)
                # idx_st = Dict(zip(varidxs(dep_nd),
                #                   get_indices_in_expr(getexpr(nd), varname(dep_nd))))
                # new_dep_ex = subs(dep_ex, idx_st)
                new_dep_ex = dep_ex
                st[getvar(dep_nd)] = new_dep_ex
            end
        end
        new_ex = subs(getexpr(nd), st)
        return copy(nd; ex=new_ex, category=:opaque)
    else
        return nd
    end
end


function fuse_broadcasting(g::ExGraph)
    new_g = reset_tape(g)
    for nd in g.tape
        if is_bcast_vec(nd)
            push!(new_g, fuse_broadcasting_node(g, new_g, nd))
        else
            push!(new_g, nd)
        end
    end
    return remove_unused(new_g, varname(g[end]))
end
