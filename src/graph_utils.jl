
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
function topsort(g::AbstractExGraph, out_vars::Vector{Symbol})
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

