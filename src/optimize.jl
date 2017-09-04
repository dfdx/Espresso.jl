
# optmizie.jl - optimize ExGraph
#
# Optimizations may be applied to 1 or several linked nodes. For example, one cross-node
# optimization transforms a pair of call that produces rank-3 tensor and aggregation operation
# into a single call that produces a matrix. E.g.:
#
#     W[i,k,j] = X[i,k] .* Y[k, j]
#     Z[i,j] = W[i,k,j]
#
# is replaced with:
#
#     Z[i,j] = X[i,k] * Y[k,j]
#
# which is an ordinary matrix-by-matrix product


const OPT_PHS = [:X, :Y, :Z, :V, :W,
                 :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]

const OPT_RULES = OrderedDict(
    :(W[i,k,j] = X[i,k] .* Y[j,k]; Z[i,j] = W[i,k,j]) =>
    :(genname__(1)[k,j] = Y[j,k]; Z[i,j] = X[i,k] * genname__(1)[k,j]),

    :(W[i,k,j] = X[i,k] .* Y[k,j]; Z[i,j] = W[i,k,j]) =>
    :(Z[i,j] = X[i,k] * Y[k,j]),

    :(W[i,j,k] = X[i] .* Y[j,k]; Z[i,j] = W[i,j,k]) =>
    :(Z[i,j] = X[i] .* Y[j,k]),

    # :(W[j,k,i] = X[i] .* Y[j,k]; Z[i,j] = W[i,j,k]) =>
    # :(Z[i,j] = X[i] .* Y[j,k]),

    :(W[k,i,j] = X[k,i] .* Y[k,j]; Z[i,j] = W[k,i,j]) =>
    :(genname__(1)[i,k] = X[k,i]; Z[i,j] = genname__(1)[i,k] * Y[k,j])
)


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



function tryoptimize(ex::Expr)
    for (pat, subs_ex) in OPT_RULES
        new_ex_nlb = tryrewrite(ex, pat, subs_ex; phs=OPT_PHS)
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


function reset_tape(g::AbstractExGraph)
    new_g = deepcopy(g)
    new_g.tape = []
    new_g.idx = Dict()
    return new_g
end


function remove_pseudoone(g::AbstractExGraph)
    g = deepcopy(g)
    I_pat = :(I[_...])
    for (i, nd) in enumerate(g.tape)
        ex = getexpr(nd)
        new_ex = without(ex, I_pat)
        if isa(nd, ExNode{:call}) && isa(new_ex, Expr) && new_ex.head != :call
            # after removing I the node changed it's type from :call to :(=)
            new_nd = copy(nd; category=:(=), ex=new_ex)
            g[i] = new_nd
        else
            setexpr!(nd, new_ex)
        end
    end
    return g
end


function optimize(g::EinGraph)
    g = remove_pseudoone(g)
    new_g = reset_tape(g)
    for nd in g.tape
        if isa(nd, ExNode{:input})
            push!(new_g, nd)
        else
            # try to optimize current node + 1st level dependencies
            ex_1 = expand_deps(g, nd, 1)
            new_ex = tryoptimize(ex_1)
            if !isnull(new_ex)
                parse!(new_g, get(new_ex))
                continue
            end
            # try to optimize only current node
            new_ex = tryoptimize(to_expr(nd))
            if !isnull(new_ex)
                parse!(new_g, get(new_ex))
                continue
            end
            # if nothing matched, add node as is
            push!(new_g, copy(nd))
        end
    end
    new_g = remove_unused(new_g,  varname(new_g[end]))
    new_g = fuse_assigned(new_g)
    return new_g
end


# common subexpression elimination

function eliminate_common(g::AbstractExGraph)
    g = reindex_from_beginning(g)
    new_g = reset_tape(g)
    existing = Dict()             # index of existing expressions
    st = Dict{Symbol,Symbol}()    # later var -> previous var with the same expression
    for nd in g.tape
        new_full_ex = subs(to_expr(nd), st)
        vname, vidxs = split_indexed(new_full_ex.args[1])
        key = (vidxs, new_full_ex.args[2])
        if haskey(existing, key) && (g[vname] |> getvalue |> size) == (g[existing[key]] |> getvalue |> size)
            st[vname] = existing[key]
        else
            C = getcategory(nd)
            push!(new_g, ExNode{C}(new_full_ex; val=getvalue(nd)))
            existing[key] = vname
        end
    end
    rename!(new_g, st)
    return new_g
end


# fuse broadcasting

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
