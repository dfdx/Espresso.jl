
# exnode.jl - ExNode, the building block of ExGraph

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


## accessors

category{C}(nd::ExNode{C}) = C

variable(nd::ExNode) = nd.var
variable!(nd::ExNode, var::Union{Symbol,Expr}) = (nd.var = var)

varname(nd::ExNode)::Symbol = isa(nd.var, Symbol) ? nd.var : nd.var.args[1]
varidxs(nd::ExNode)::Vector = isa(nd.var, Symbol) ? [] : nd.var.args[2:end]

expr(nd::ExNode) = nd.ex
expr!(nd::ExNode, ex) = (nd.ex = ex)

guards(nd::ExNode) = nd.guars
guards!(nd::ExNode, guards::Vector{Expr}) = (nd.guards = guards)

value(nd::ExNode) = nd.val
value!(nd::ExNode, val) = (nd.val = val)

Base.copy{C}(nd::ExNode{C}; category=C, var=nd.var, ex=nd.ex,  guards=nd.guards, val=nd.val) =
    ExNode{category}(var, ex, guards, val)


## to_expr and friends

"""
Convert ExNode to a full expression, e.g. for vectorized notation:

    z = x + y

or for indexed notation:

    z[i] = x[i] + y[i]
"""
to_expr(nd::ExNode) = :($(variable(nd)) = $(expr(nd)))


"""
Convert ExNode to a fortmat compatible with Einsum.jl
"""
function to_einsum_expr(nd::ExNode)
    ex_without_I = without(expr(nd), :(I[_...]))
    assign_ex = Expr(:(:=), variable(nd), ex_without_I)
    return Expr(:macrocall, Symbol("@einsum"), assign_ex)
end


## dependencies

"""Get names of dependenices of this node"""
dependencies(nd::ExNode{:input}) = Symbol[]
dependencies(nd::ExNode{:constant}) = Symbol[]
dependencies(nd::ExNode{:(=)}) = get_var_names(expr(nd))
dependencies(nd::ExNode{:call}) = get_var_names(expr(nd))
dependencies(nd::ExNode{:bcast}) = get_var_names(expr(nd))


function Base.show{C}(io::IO, nd::ExNode{C})
    val = isa(value(nd), AbstractArray) ? "<$(typeof(nd.val))>" : nd.val
    print(io, "ExNode{$C}($(to_expr(nd)) | $val)")
end

isindexed(nd::ExNode) = any(isref, get_vars(expr(nd)))
