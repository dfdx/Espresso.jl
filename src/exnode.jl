
# exnode.jl - ExNode, the building block of ExGraph
#
# There are several categories of ExNodes:
#
#  * :call     - single function call, e.g. ExNode{:call}(z = x + y)
#  * :bcast    - broadcasting, e.g. ExNode{:bcast}(y = exp.(x))
#  * :(=)      - assignment, e.g. ExNode{:(=)}(y = x)
#  * :input    - input variable
#  * :constant - constant, e.g. ExNode{:constant}(x = 42)
#  * :opaque   - unparsed expression that can contain any subexpression;
#                a graph with opaque nodes isn't valid for most tasks,
#                but it may be converted to normalized graph using `reparse(g)`

# exnode

@runonce mutable struct ExNode{C}  # C - category of node, e.g. :call, :=, etc.
    var::Union{Symbol, Expr}       # variable name, possibly with indices
    ex::Any                        # simple expression that produces the var
    guards::Vector{Expr}           # guards, turning ex to 0 when false
    val::Any                       # example value
end

function ExNode{C}(var::Union{Symbol,Expr}, ex::Any; guards=[], val=nothing) where C
    return ExNode{C}(var, ex, guards, val)
end

function ExNode{C}(full_ex::Expr; val=nothing) where C
    @assert full_ex.head == :(=)
    var = full_ex.args[1]
    ex = without_guards(full_ex.args[2])
    guards = find_guards(full_ex.args[2])
    return ExNode{C}(var, ex; guards=guards, val=val)
end


## accessors

getcategory(nd::ExNode{C}) where {C} = C

getvar(nd::ExNode) = nd.var
setvar!(nd::ExNode, var::Union{Symbol,Expr}) = (nd.var = var)

varname(nd::ExNode)::Symbol = isa(nd.var, Symbol) ? nd.var : nd.var.args[1]
varidxs(nd::ExNode)::Vector = isa(nd.var, Symbol) ? [] : nd.var.args[2:end]

getexpr(nd::ExNode) = nd.ex
setexpr!(nd::ExNode, ex::Any) = (nd.ex = ex)

getguards(nd::ExNode) = nd.guards
setguards!(nd::ExNode, guards::Vector{Expr}) = (nd.guards = guards)

getvalue(nd::ExNode) = nd.val
setvalue!(nd::ExNode, val) = (nd.val = val)

Base.copy(nd::ExNode{C}; category=C, var=nd.var, ex=nd.ex,  guards=nd.guards, val=nd.val) where {C} =
    ExNode{category}(var, ex, guards, val)


## to_expr and friends

"""
Convert ExNode to a full expression, e.g. for vectorized notation:

    z = x + y

or for indexed notation:

    z[i] = x[i] + y[i]
"""
function to_expr(nd::ExNode)
    var = getvar(nd)
    ex = with_guards(getexpr(nd), getguards(nd))
    return :($var = $ex)
end


"""
Convert ExNode to a fortmat compatible with Einsum.jl
"""
function to_einsum_expr(nd::ExNode)
    ex = getexpr(nd)
    v = varname(nd)
    assign_ex = Expr(:(:=), getvar(nd), ex)
    macrocall_ex = Expr(:macrocall, Symbol("@einsum"), assign_ex)
    return Expr(:block, macrocall_ex)
end

function to_einsum_expr(nd::ExNode, var_size)
    ex = getexpr(nd)
    v = varname(nd)
    init_ex = :($v = zeros($(var_size)))  # TODO: handle data types other than Float64
    assign_ex = Expr(:(=), getvar(nd), ex)
    macrocall_ex = Expr(:macrocall, Symbol("@einsum"), assign_ex)
    return Expr(:block, init_ex, macrocall_ex)
end


## dependencies

"""Get names of dependenices of this node"""
dependencies(nd::ExNode{:input}) = Symbol[]
dependencies(nd::ExNode{:constant}) = Symbol[]
dependencies(nd::ExNode{:(=)}) = get_var_names(getexpr(nd))
dependencies(nd::ExNode{:call}) = get_var_names(getexpr(nd))
dependencies(nd::ExNode{:bcast}) = get_var_names(getexpr(nd))
dependencies(nd::ExNode{:tuple}) = [split_indexed(dep)[1] for dep in getexpr(nd).args]
dependencies(nd::ExNode{:opaque}) = get_var_names(getexpr(nd); rec=true)


## node utils

# varsize(nd::ExNode{:tuple}) = map(size, getvalue(nd))
# varsize(nd::ExNode) = size(getvalue(nd))

# buffer_expr(nd::ExNode{:tuple})


function Base.show(io::IO, nd::ExNode{C}) where C
    val = isa(getvalue(nd), AbstractArray) ? "<$(typeof(getvalue(nd)))>" : getvalue(nd)
    ex_str = "ExNode{$C}($(to_expr(nd)) | $val)"
    # print(io, replace(ex_str, "Colon()", ":"))
    print(io, ex_str)
end

isindexed(nd::ExNode) = any(isref, get_vars(to_expr(nd)))


function rewrite(nd::ExNode{C}, pat, rpat; rw_opts...) where C
    full_ex = to_expr(nd)
    new_full_ex = rewrite(full_ex, pat, rpat; rw_opts...)
    @assert new_full_ex.head == :(=)
    var, ex = new_full_ex.args[1:2]
    return copy(nd; category=:opaque, var=var, ex=ex, val=nothing)
end
