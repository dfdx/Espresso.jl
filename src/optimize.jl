
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

    :(W[k,i,j] = X[k,i] .* Y[k,j]; Z[i,j] = W[k,i,j]) =>
    :(genname__(1)[i,k] = X[k,i]; Z[i,j] = genname__(1)[i,k] * Y[k,j])
)


function expand_deps!(g::ExGraph, nd::ExNode{:input}, depth::Int, result::Vector{Expr})
    # do nothing
end

function expand_deps!(g::ExGraph, nd::ExNode{:constat}, depth::Int, result::Vector{Expr})
    push!(result, to_expr(nd))
end

function expand_deps!(g::ExGraph, nd::ExNode{:(=)}, depth::Int, result::Vector{Expr})
    if depth > 0
        expand_deps!(g, [g[var] for var in dependencies(nd)], depth - 1, result)
        push!(result, to_expr(nd))
    end
end

function expand_deps!(g::ExGraph, nd::ExNode{:call}, depth::Int, result::Vector{Expr})
    if depth > 0
        for dep in dependencies(nd)
            expand_deps!(g, g[end], depth - 1, result)
        end
        push!(result, to_expr(nd))
    end
end


function collect_deps!(result::Set{Symbol}, g::ExGraph, nd::ExNode, depth::Int=typemax(Int))
    if depth > 0
        for dep in dependencies(nd)
            if haskey(g, dep)
                collect_deps!(result, g, g[dep], depth - 1)
            end
        end
    end
    push!(result, varname(nd))
end


function collect_deps(g::ExGraph, nd::ExNode, depth::Int=typemax(Int))
    result = Set{Symbol}()
    collect_deps!(result, g, nd, depth)
    return result
end


function expand_deps(g::ExGraph, nd::ExNode, depth::Int=typemax(Int))
    deps = collect_deps(g, nd, depth)
    ex = Expr(:block)
    for nd in g.tape
        if !isa(nd, ExNode{:input}) && in(varname(nd), deps)
            push!(ex.args, to_expr(nd))
        end
    end
    return ex
end


function remove_unused(g::ExGraph, output_var::Symbol)
    deps = collect_deps(g, g[output_var])
    gr = reset_tape(g)
    for nd in g.tape
        if in(varname(nd), deps)
            addnode!(gr, nd)
        end
    end
    return gr
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


function reset_tape(g::ExGraph)
    new_g = deepcopy(g)
    new_g.tape = []
    new_g.idx = Dict()
    return new_g
end


function remove_pseudoone(g::ExGraph)
    g = deepcopy(g)
    I_pat = :(I[_...])
    for nd in g.tape
        ex = expr(nd)        
        new_ex = without(ex, I_pat)
        expr!(nd, new_ex)
    end
    return g
end


function optimize(g::ExGraph)
    g = remove_pseudoone(g)
    new_g = reset_tape(g)    
    known_names = Set(varname(nd) for nd in g.tape)
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
            addnode!(new_g, nd)
        end
    end
    new_g = remove_unused(new_g,  varname(new_g[end]))
    collapse_assignments!(new_g)
    return new_g
end
