
# tensor_deriv.jl - tensor derivative utils (using Einstein notation)

const TDIFF_PHS = [:A, :B, :C, :X, :Y, :Z,
                   :i, :j, :k, :l, :m, :n, :p, :q, :r, :s, :t]


## tensor derivative type

type TensorDeriv <: AbstractDeriv
    dvar::Expr            # variable being differented, e.g. dz[i,j]
    wrt::Expr             # variable w.r.t. which we differentiate, e.g. dx[m,n]
    ex::Any               # derivative expression, e.g. :(y[j, n]) or 1
    guards::Vector{Expr}  # guards for non-zero elements e.g. [:(j == m)]
end

function TensorDeriv(dex::Expr)
    dvar, wrt = dex.args[1].args[2:3]
    ex = without_guards(dex.args[2])
    guards = get_guards(dex.args[2])
    return TensorDeriv(dvar, wrt, ex, guards)
end

function Base.show(io::IO, td::TensorDeriv)
    grds = (length(td.guards) > 0 ?
            (" * " * join(["($g)" for g in td.guards], " * ")) : "")    
    print(io, "$(td.dvar)/$(td.wrt) = $(td.ex) $grds")
end

function Base.copy(td::TensorDeriv; dvar=td.dvar, wrt=td.wrt,
              ex=td.ex, guards=td.guards)
    return TensorDeriv(dvar, wrt, ex, guards)
end

expr(td::TensorDeriv) = td.ex
var_indices(td::TensorDeriv) = convert(Vector{Symbol}, td.dvar.args[2:end])
wrt_indices(td::TensorDeriv) = convert(Vector{Symbol}, td.wrt.args[2:end])
deriv_indices(td::TensorDeriv) = vcat(var_indices(td), wrt_indices(td))

function to_expr(td::TensorDeriv)
    # dvarname, dvaridxs = string(td.dvar.args[1]), td.dvar.args[2:end]
    # wrtname, wrtidxs = string(td.wrt.args[1]), td.wrt.args[2:end]
    # lhs = Expr(:ref, Symbol(dvarname, wrtname), dvaridxs..., wrtidxs...)
    lhs = :($(td.dvar) / $(td.wrt))
    rhs = length(td.guards) > 0 ? Expr(:call, :*, td.ex, td.guards...) : td.ex
    return Expr(:(=), lhs, rhs)
end



"""
Given a set of existing indices and current position of iterator,
find the next index not in the set.
"""
function next_index(existing::Set{Symbol}, pos::Int)
    while pos <= length(IDX_NAMES) && in(IDX_NAMES[pos], existing)
        pos += 1
    end
    if pos <= length(IDX_NAMES)
        return IDX_NAMES[pos], pos + 1
    else
        throw(BoundsError("IDX_NAMES"))
    end
end


"""
Given a set of existing indicies and possibly duplicates, find for each duplicate
a replacement - index from IDX_NAMES that is not used yet.
"""
function index_replacements(existing::Set{Symbol}, maybedups::Vector{Symbol})
    repls = Dict{Symbol,Symbol}()
    pos = 1
    for idx in maybedups
        if in(idx, existing) && !in(idx, keys(repls))
            repls[idx], pos = next_index(union(existing, Set(keys(repls))), pos)
        end
    end
    return repls
end



function reindex_with_guards(td::TensorDeriv)
    DI = union(Set{Symbol}(td.dvar.args[2:end]), Set{Symbol}(td.wrt.args[2:end]))
    pairs = Tuple{Symbol,Symbol}[(grd.args[2], grd.args[3]) for grd in td.guards]
    st, new_pairs = reduce_equalities(pairs, DI)
    new_guards = [:($i1 == $i2) for (i1, i2) in new_pairs]
    new_ex = subs(td.ex, st)
    return copy(td; ex=new_ex, guards=new_guards)
end


function *(td1::TensorDeriv, td2::TensorDeriv)
    # can only multiply related derivatives, e.g. dz/dy * dy/dx
    @assert td1.wrt.args[1] == td2.dvar.args[1]
    common_idxs_st = Dict(zip(var_indices(td2), wrt_indices(td1)))
    other_idxs_st = index_replacements(Set(deriv_indices(td1)),
                                       wrt_indices(td2))
    st = merge(common_idxs_st, other_idxs_st)
    wrt2_reindexed = subs(td2.wrt, st)
    ex2_reindexed = subs(expr(td2), st)
    guards2_reindexed = Expr[subs(g, st) for g in td2.guards]
    new_ex = simplify(expr(td1) * ex2_reindexed)
    new_guards = vcat(td1.guards, guards2_reindexed)
    new_td = TensorDeriv(td1.dvar, wrt2_reindexed, new_ex, new_guards)
    return reindex_with_guards(new_td)
end


function +(td1::TensorDeriv, td2::TensorDeriv)
    @assert td1.dvar.args[1] == td2.dvar.args[1]
    @assert td1.wrt.args[1] == td2.wrt.args[1]
    dvar_idxs_st = Dict(zip(var_indices(td2), var_indices(td1)))
    wrt_idxs_st = Dict(zip(wrt_indices(td2), wrt_indices(td1)))
    st = merge(dvar_idxs_st, wrt_idxs_st)
    wrt2_reindexed = subs(td2.wrt, st)
    ex2_reindexed = subs(expr(td2), st)
    guards2_reindexed = Expr[subs(g, st) for g in td2.guards]
    new_ex = simplify(expr(td1) + ex2_reindexed)
    new_guards = vcat(td1.guards, guards2_reindexed)
    new_td = TensorDeriv(td1.dvar, wrt2_reindexed, new_ex, new_guards)
    return reindex_with_guards(new_td)
end




## tensor differentiation rules

immutable TensorDiffRule <: AbstractDiffRule
    pat::Expr             # pattern of expression to differentiate
    deriv::TensorDeriv    # pattern of differentiation expression
end



# read as: (operation name, [indices], diff var index)
# typealias TensorDiffKey Tuple{Symbolic, Vector{Vector{Symbol}}, Int}

# const TENSOR_DIFF_RULES = Dict{TensorDiffKey, DiffRule}()

const TENSOR_DIFF_RULES = Dict{Tuple{OpName, Int}, Vector{TensorDiffRule}}()

function _tdiff_rule(ex, dex)
    op = canonical(current_module(), ex.args[2].args[1])
    idxs = get_indices(ex.args[2])
    dvar = dex.args[1].args[2]
    wrt = dex.args[1].args[3]
    deriv_ex = without_guards(sanitize(dex.args[2]))
    guards = get_guards(dex)
    deriv = TensorDeriv(dvar, wrt, deriv_ex, guards)
    diff_var_name = Symbol(string(wrt.args[1])[2:end])
    var_names = [iex.args[1] for iex in ex.args[2].args[2:end]]
    deriv_idx = find(var_names .== diff_var_name)[1]
    rule = TensorDiffRule(ex, deriv)
    if !haskey(TENSOR_DIFF_RULES, (op, deriv_idx))
        TENSOR_DIFF_RULES[(op, deriv_idx)] = TensorDiffRule[]
    end
    push!(TENSOR_DIFF_RULES[(op, deriv_idx)], rule)
end


macro tdiff_rule(ex, dex)
    _tdiff_rule(ex, dex)
    nothing
end




function tfind_rule(fullex::Expr, idx::Int)
    @assert fullex.head == :(=) && fullex.args[2].head == :call
    op = fullex.args[2].args[1]
    haskey(TENSOR_DIFF_RULES, (op, idx)) || error("Can't find rule for `$fullex`")
    rules = TENSOR_DIFF_RULES[(op, idx)]
    matching = findfirst(pat -> !isnull(matchex(pat, fullex; phs=TDIFF_PHS)),
                         [r.pat for r in rules])
    matching != 0 || error("Can't find rule for `$fullex`")
    return rules[matching]
end

dname(var::Symbol) = Symbol("d$var")
undname(dvar::Symbol) = Symbol(string(dvar)[2:end])


"""dZ[i]/dX[j] = ... ==> Z[i]/X[i] = ..."""
function unpack_deriv(ex::Expr)
    @assert ex.head == :(=)
    @assert ex.args[1].head == :call && ex.args[1].args[1] == :/
    dvar, dwrt = [dv.args[1] for dv in ex.args[1].args[2:3]]
    var, wrt = undname(dvar), undname(dwrt)
    return subs(ex, Dict(dvar => var, dwrt => wrt))
end

"""Z[i]/X[j] = ... ==> dZ[i]/dX[i] = ..."""
function pack_deriv(ex::Expr)
    @assert ex.head == :(=)
    @assert ex.args[1].head == :call && ex.args[1].args[1] == :/
    var, wrt = [v.args[1] for v in ex.args[1].args[2:3]]
    dvar, dwrt = dname(var), dname(wrt)
    return subs(ex, Dict(var => dvar, wrt => dwrt))
end


# TODO: if rule isn't found, treat it as elementwise function call
function tderivative(fullex::Expr, idx::Int)
    rule = tfind_rule(fullex, idx)
    unpacked_dpat = unpack_deriv(to_expr(rule.deriv))
    unpacked_dex = rewrite(fullex, rule.pat, unpacked_dpat; phs=TDIFF_PHS)
    dex = pack_deriv(unpacked_dex)
    return TensorDeriv(dex)
end

function tderivative(fullex::Expr, dvar::Symbol)
    dvars = [idvar.args[1] for idvar in indexed_vars(fullex.args[2])]
    matching = findfirst(dvars .== dvar)
    matching != 0 || error("Variable `$dvar` isn't present " *
                           "in expression `$fullex`")    
    return tderivative(fullex, matching[1])
end


function main_yahd()
    fullex = :(c[i,j] = a[i,k] * b[k,j])
    deriv = tderivative(fullex, 1)
end




# matrix-by-matrix product
@tdiff_rule (Z[i,j] = X[i,k] * Y[k,j]) (dZ[i,j]/dX[m,n] = Y[n,j] * (i == m))
@tdiff_rule (Z[i,j] = X[i,k] * Y[k,j]) (dZ[i,j]/dY[m,n] = X[i,m] * (n == j))

# inner product of 2 vectors
@tdiff_rule (Z[] = X[i] * Y[i]) (dZ[]/dX[i] = Y[i])
@tdiff_rule (Z[] = X[i] * Y[i]) (dZ[]/dY[i] = X[i])

# outer product of 2 vectors
@tdiff_rule (Z[i,j] = X[i] * Y[j]) (dZ[i,j]/dX[m] = Y[j] * (i == m))
@tdiff_rule (Z[i,j] = X[i] * Y[j]) (dZ[i,j]/dY[m] = X[i] * (j == m))

# some element-wise functions
@tdiff_rule (Z[i] = X[i] + Y[i]) (dZ[i]/dX[j] = 1 * (i == j))
@tdiff_rule (Z[i] = X[i] + Y[i]) (dZ[i]/dY[j] = 1 * (i == j))
@tdiff_rule (Z[i,j] = X[i,j] + Y[i,j]) (dZ[i,j]/dX[k,l] = 1 * (i == k) * (j == l))
@tdiff_rule (Z[i,j] = X[i,j] + Y[i,j]) (dZ[i,j]/dY[k,l] = 1 * (i == k) * (j == l))
