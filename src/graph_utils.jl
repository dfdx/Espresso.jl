
## topological sort

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
            if haskey(dpts, dep)          # don't include global constants
                push!(dpts[dep], vname)
            end
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


## expand const

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


reindex_from_beginning(g::ExGraph) = g


## inline / inline unknown

function subgraph_interm_subs_table(sub_g::ExGraph, dont_subs; prefix="")
    interm_vars = [varname(sub_nd) for sub_nd in sub_g.tape
                   if !in(varname(sub_nd), dont_subs)]
    new_names = [genname("$(prefix)_$(v)_") for v in interm_vars]
    return Dict(zip(interm_vars, new_names))
end


"""
Find definition of a called function and build its subgraph ready for inlining
"""
function make_subgraph(g::ExGraph, nd::ExNode{:call})
    mod = @get(g.ctx, :mod, Main)  # TODO: Main or current_graph()?
    fname = getexpr(nd).args[1]
    f = Core.eval(mod, fname)
    args = dependencies(nd)
    arg_types = ([typeof(getvalue(g[arg])) for arg in args]...,)
    params, sub_ex = funexpr(f, arg_types)
    sub_g = ExGraph(sub_ex; ctx=g.ctx)
    st = Dict(zip(params, args))           # rename internal params to actual arguments
    st[varname(sub_g[end])] = varname(nd)  # rename output var to this node's
    dont_subs = Set(keys(st))
    st = merge(st, subgraph_interm_subs_table(sub_g, dont_subs; prefix=fname))
    rename!(sub_g, st)
    return sub_g
end


function inline_subgraphs(g::ExGraph, inline_subs::Dict{Symbol, ExGraph})
    new_g = reset_tape(g)
    for nd in g
        vname = varname(nd)
        if haskey(inline_subs, vname)
            for sub_nd in inline_subs[vname]
                push!(new_g, sub_nd)
            end
        else
            push!(new_g, nd)
        end
    end
    return new_g
end


function inline_nodes(g::ExGraph, vnames::Set{Symbol})
    inline_subs = Dict(vname => make_subgraph(g, g[vname]) for vname in vnames)
    return inline_subgraphs(g, inline_subs)
end



iscall(x) = isa(x, Expr) && x.head == :call

function convert_call(g::AbstractExGraph, nd::Union{ExNode{:call}, ExNode{:bcast}})
    new_ex = expand_const(g, getexpr(nd)) |> simplify
    if isa(new_ex, Symbol) || (isa(new_ex, Expr) && new_ex.head == :ref)
        # convert to assignment
        return copy(nd; category=:(=), ex=new_ex)
    elseif isa(new_ex, Number) || isa(new_ex, AbstractArray)
        # convert to constant
        if haskey(g.ctx, :bitness)
            new_ex = force_bitness(new_ex, Val(g.ctx[:bitness]))
        end
        return copy(nd; category=:constant, ex=new_ex)
    elseif isa(new_ex, Tuple)
        return copy(nd; category=:tuple, ex=new_ex)
    else
        error("Call node $nd is simplified to an unknown non-call $new_ex")
    end
end


"""
Given a symbolic name, either adds `2` to the end
or increment existing number. Example:

    inc_var_name(:x)   # ==> x2
    inc_var_name(:x2)  # ==> x3

"""
function inc_var_name(var::Symbol)
    svar = string(var)
    r = match(r"(.*)(\d+)", svar)
    if r != nothing
        base = r.captures[1]
        num = parse(Int, r.captures[2]) + 1
        return Symbol("$base$num")
    else
        return Symbol("$(svar)2")
    end
end



function rename_from_beginning(g::ExGraph)
    new_g = deepcopy(g)
    vars = [getvar(nd) for nd in g]
    new_vars = [Symbol("var$i") for i=1:length(vars)]
    st = Dict(zip(vars, new_vars))
    rename!(new_g, st)
    return new_g
end


"""
A single number to represent a graph.
Insensitive to variable names.
"""
function graph_hash(g::ExGraph)
    return rename_from_beginning(g) |> to_expr |> hash
end
