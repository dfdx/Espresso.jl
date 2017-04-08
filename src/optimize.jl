
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


function remove_unused(g::AbstractExGraph, output_var::Symbol)
    deps = collect_deps(g, g[output_var])
    gr = reset_tape(g)
    for nd in g.tape
        if in(varname(nd), deps)
            addnode!(gr, nd)
        end
    end
    return gr
end


# """
# Removes unused variables from multiline expressions, e.g. in:

#     x = u * v
#     y = x + 1
#     z = 2x

# `y` isn't used to compute output variable `z`, so it's removed:

#     x = u * v
#     z = 2x

# """
# function remove_unused(ex::Expr, output_var::Symbol)
#     ex.head == :block || return ex  # nothing to remove
#     g = ExGraph(ex)
#     deps = collect_deps(g, g[output_var])
#     push!(deps, output_var)
#     res = quote end
#     for subex in ex.args
#         if subex.head == :(=)
#             vname = split_indexed(subex.args[1])[1]
#             if in(vname, deps)
#                 push!(res.args, subex)
#             end
#         else
#             push!(res.args, subex)
#         end
#     end
#     return res
# end


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
        ex = expr(nd)
        new_ex = without(ex, I_pat)
        if isa(nd, ExNode{:call}) && isa(new_ex, Expr) && new_ex.head != :call
            # after removing I the node changed it's type from :call to :(=)
            new_nd = copy(nd; category=:(=), ex=new_ex)
            g[i] = new_nd
        else
            expr!(nd, new_ex)
        end
    end
    return g
end


function optimize(g::EinGraph)
    g = remove_pseudoone(g)
    new_g = reset_tape(g)
    for nd in g.tape
        if isa(nd, ExNode{:input})
            addnode!(new_g, nd)
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
            addnode!(new_g, copy(nd))
        end
    end
    new_g = remove_unused(new_g,  varname(new_g[end]))
    collapse_assignments!(new_g)
    return new_g
end
