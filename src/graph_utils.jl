
# topological sort

"""
For each variable in graph, calculate all variables that depend on it.
This is essentially the opposite of `dependencies(nd::ExNode)`, but
operates on variable names rather than nodes.
"""
function dependents(g::AbstractExGraph)
    dpts = Dict{Symbol, Vector{Symbol}}()
    # prepare all dependent lists
    for nd in g.tape
        dpts[varname(nd)] = Symbol[]
    end
    for nd in g.tape
        vname = varname(nd)
        for dep in dependencies(nd)
            push!(dpts[dep], vname)
        end
    end
    return dpts
end



function topsort_visit!(g::AbstractExGraph, dpts::Dict{Symbol, Vector{Symbol}},
                        temp_marked::Set{Symbol}, perm_marked::Set{Symbol},
                        sorted::Vector{Symbol}, vname::Symbol)
    if vname in temp_marked
        error("Expression graph isn't a DAG!")
    end
    if !in(vname, temp_marked) && !in(vname, perm_marked)        
        push!(temp_marked, vname)
        for dpt in dpts[vname]
            topsort_visit!(g, dpts, temp_marked, perm_marked, sorted, dpt)
        end
        push!(perm_marked, vname)
        delete!(temp_marked, vname)
        push!(sorted, vname)
    end    
end


"""Sort graph topologically"""
function topsort(g::AbstractExGraph)
    dpts = dependents(g)
    sorted = Symbol[]
    temp_marked = Set{Symbol}()
    perm_marked = Set{Symbol}()
    for vname in keys(dpts)
        topsort_visit!(g, dpts, temp_marked, perm_marked, sorted, vname)
    end
    sg  = Espresso.reset_tape(g)   
    for vname in reverse(sorted)
        push!(sg, g[vname])
    end
    return sg
end


# expand const

"""Expand all constant vars in a given expression"""
function expand_const(g::AbstractExGraph, ex)
    st = Dict{Symbol, Any}()
    vnames = get_var_names(ex)
    for vname in vnames
        if haskey(g, vname) && isa(g[vname], ExNode{:constant})
            # st[vname] = g[vname].val
            st[vname] = getvalue(g[vname])
        end
    end
    return subs(ex, st)
end

# reindex from beginning

function reindex_from_beginning(g::EinGraph)
    new_g = reset_tape(g)
    for nd in g.tape
        full_ex = to_expr(nd)
        idxs = unique(flatten(get_indices(full_ex)))
        idxs = [idx for idx in idxs if idx != :(:)]  # skip [:] indices
        new_idxs = IDX_NAMES[1:length(idxs)]
        st = Dict(zip(idxs, new_idxs))
        new_full_ex = subs(full_ex, st)
        C = getcategory(nd)
        push!(new_g, ExNode{C}(new_full_ex; val=getvalue(nd)))
    end
    return new_g
end


reindex_from_beginning(g::ExGraph) = g
