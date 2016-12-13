
# exgraph.jl - expression graph as a list of primitive expression nodes

# exnode

@runonce type ExNode{C}         # C - category of node, e.g. :call, :=, etc.
    var::Symbol                 # variable name
    ex::Any                     # simple expression that produces name
    idxs::Vector{Vector}        # indexes (var : args) if in Einstein notation
    val::Any                    # example value
end

ExNode(C::Symbol, var::Symbol, ex::Any) = ExNode{C}(var, ex, [], nothing)

# category{C}(nd::ExNode{C}) = C
variable(nd::ExNode) = nd.var
value(nd::ExNode) = nd.val
expr(nd::ExNode) = nd.ex
function iexpr(nd::ExNode)
    varex = Expr(:ref, nd.var, nd.idxs[1]...)
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    depex = add_indices(nd.ex, s2i)
    return depex
end


## deps

"""Get symbols of dependenices of this node"""
dependencies(nd::ExNode{:input}) = Symbol[]
dependencies(nd::ExNode{:constant}) = Symbol[]
dependencies(nd::ExNode{:(=)}) = [nd.ex]
dependencies(nd::ExNode{:call}) = nd.ex.args[2:end]

to_expr(nd::ExNode) = :($(nd.var) = $(nd.ex))
function to_einsum_expr(nd::ExNode)
    varidxs = nd.idxs[1]
    varex = length(varidxs) > 0 ? Expr(:ref, nd.var, varidxs...) : nd.var     
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    ex_without_I = without(nd.ex, :I)
    depex = add_indices(ex_without_I, s2i)
    assign_ex = Expr(:(:=), varex, depex)
    return Expr(:macrocall, Symbol("@einsum"), assign_ex)
end

function to_iexpr(nd::ExNode)
    varex = maybe_indexed(nd.var, nd.idxs[1])
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    depex = add_indices(nd.ex, s2i)
    return Expr(:(=), varex, depex)
end

function Base.show{C}(io::IO, nd::ExNode{C})
    val = isa(nd.val, AbstractArray) ? "<$(typeof(nd.val))>" : nd.val
    print(io, "ExNode{$C}($(to_expr(nd)) | $val)")
end

isindexed(nd::ExNode) = !isempty(nd.idxs) && any(x -> !isempty(x), nd.idxs)


# exgraph

@runonce type ExGraph
    tape::Vector{ExNode}           # list of ExNode's
    idx::Dict{Symbol, ExNode}      # map from var name to its node in the graph
    ctx::Dict{Any,Any}             # settings and caches
end

function ExGraph(ex::Expr; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    @get_or_create(ctx, :mod, current_module())
    ctx[:ex] = ex
    g = ExGraph(ExNode[], Dict(), ctx)
    for (var, val) in inputs
        addnode!(g, :input, var, var; val=val)
    end
    for (var, val) in get(ctx, :constants, [])
        addnode!(g, :constant, var, var; val=val)
    end
    parse!(g, ex)
    collapse_assignments!(g)
    return g
end

function Base.show(io::IO, g::ExGraph)
    print(io, "ExGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end

Base.haskey(g::ExGraph, var::Symbol) = haskey(g.idx, var)
Base.get(g::ExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::ExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::ExGraph, i::Integer) = g.tape[i]
Base.endof(g::ExGraph) = endof(g.tape)

## """Extract symbols that may make conflicts with temporary names in ExGraph"""
function possible_temp_names(ex::Expr)
    names = unique(flatten(map(possible_temp_names, ex.args)))
    return convert(Vector{Symbol}, names)
end

possible_temp_names(name::Symbol) = (startswith(string(name), "tmp") ?
                                     [name] :
                                     Symbol[])
possible_temp_names(x) = Symbol[]


"""Generate new unique name for intermediate variable in graph"""
function genname(ctx::Dict{Any,Any})
    last_id = @get_or_create(ctx, :last_id, 1)
    possible_names = @get_or_create(ctx, :possible_names,
                                    possible_temp_names(ctx[:ex]))
    name = Symbol("tmp$(last_id)")
    while in(name, possible_names)
        last_id += 1
        name = Symbol("tmp$(last_id)")
    end
    ctx[:last_id] = last_id + 1
    return name
end


## addnode!

"""
Add new node to a graph. Expression should be simple, e.g.
nested calls or blocks are not allowed (use parse!() for it).
"""
function addnode!(g::ExGraph, C::Symbol, var::Symbol, ex::Any;
                  idxs=Vector[], val=nothing)
    nd = ExNode{C}(var, ex, idxs, val)
    push!(g.tape, nd)
    g.idx[var] = nd
    return var
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

## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the name of the output variable.
"""
parse!(g::ExGraph, ex::Expr) = parse!(g, to_exh(ex))
parse!(g::ExGraph, ::LineNumberNode) = (:nil, Symbol[])
parse!(g::ExGraph, ::ExH{:line}) = (:nil, Symbol[])
parse!(g::ExGraph, s::Symbol) = (s, Symbol[])
parse!(g::ExGraph, gr::GlobalRef) = (gr, Symbol[])

function parse!(g::ExGraph, x::Number)
    var = addnode!(g, :constant, genname(g.ctx), x; val=x)
    return var, Symbol[]
end

function parse!(g::ExGraph, x::AbstractArray)
    name = addnode!(g, :constant, genname(g.ctx), x; val=x)
    return name, Symbol[]
end

split_indexed(name::Symbol) = (name, Symbol[])
split_indexed(ex::Expr) = (ex.args[1], convert(Vector{Symbol}, ex.args[2:end]))

function parse!(g::ExGraph, ex::ExH{:(=)})
    lhs, rhs = ex.args
    var, varidxs = split_indexed(lhs)
    dep, depidxs = parse!(g, rhs)
    idxs = Vector{Symbol}[varidxs, depidxs]
    addnode!(g, :(=), var, dep; idxs=idxs)
    return var, varidxs
end


function parse!(g::ExGraph, ex::ExH{:ref})
    return ex.args[1], convert(Vector{Symbol}, ex.args[2:end])
end


function parse!(g::ExGraph, ex::ExH{:call})
    op = canonical(g.ctx[:mod], ex.args[1])
    deps, depidxs = unzip([parse!(g, arg) for arg in ex.args[2:end]])
    sex = Expr(:call, op, deps...)
    varidxs = forall_indices(op, depidxs)
    idxs = insert!(copy(depidxs), 1, varidxs)
    var = addnode!(g, :call, genname(g.ctx), sex; idxs=idxs)
    return var, varidxs
end

function parse!(g::ExGraph, ex::ExH{:block})
    name_idxs = [parse!(g, arg) for arg in ex.args]
    return name_idxs[end]
end

function parse!(g::ExGraph, ex::ExH{:body})
    name_idxs = [parse!(g, arg) for arg in ex.args]
    return name_idxs[end]
end


## evaluate!

"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
evaluate!(g::ExGraph, node::ExNode{:constant}) = node.val
evaluate!(g::ExGraph, node::ExNode{:input}) = node.val


function mk_eval_expr(g::ExGraph, nd::ExNode)
    dep_nodes = [g.idx[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = [(nd.var, nd.val) for nd in dep_nodes]
    block = Expr(:block)
    for (dep, val) in deps_vals
        push!(block.args, Expr(:(=), dep, val))
    end
    push!(block.args, isindexed(nd) ? to_einsum_expr(nd) : to_expr(nd))
    push!(block.args, nd.var)
    return block
end


function evaluate!(g::ExGraph, nd::ExNode{:(=)})
    if (nd.val != nothing) return nd.val end
    depnd = g.idx[dependencies(nd)[1]]
    evaluate!(g, depnd)
    evex = mk_eval_expr(g, nd)
    nd.val = eval(evex)
    return nd.val
end

function evaluate!(g::ExGraph, nd::ExNode{:call})
    if (nd.val != nothing) return nd.val end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)            
            evaluate!(g, g[dep])
        end
    end
    evex = mk_eval_expr(g, nd)
    nd.val = eval(evex)
    return nd.val
end

evaluate!(g::ExGraph, name::Symbol) = evaluate!(g, g.idx[name])


# graph simlification

function collapse_assignments!(g::ExGraph)
    st = Dict{Symbol, Symbol}()
    for nd in g.tape
        nd.ex = subs(nd.ex, st)
        if isa(nd, ExNode{:(=)}) &&
            (length(nd.idxs) == 0 || nd.idxs[1] == nd.idxs[2])
            st[nd.var] = dependencies(nd)[1]
        end
    end
    new_tape = Vector{ExNode}()
    new_idx = Dict{Symbol, ExNode}()
    for nd in g.tape
        if !haskey(st, nd.var)
            push!(new_tape, nd)
            new_idx[nd.var] = nd
        end
    end
    g.tape = new_tape
    g.idx = new_idx
end
