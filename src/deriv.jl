
# diff_base.jl - common routines for ordinary symbolic and tensor differentiation

abstract AbstractDeriv

immutable Deriv
    dvar::Symbol
    wrt::Symbol
    ex::Any
end

function *(d1::Deriv, d2::Deriv)
    # assert chain rule (we might not need it, but let's try)
    @assert d1.wrt == d2.dvar 
    return Deriv(d1.dvar, d2.wrt, d1.ex * d2.ex)
end


abstract AbstractDiffRule

immutable DiffRule <: AbstractDiffRule
    ex::Expr        # pattern of expression to differentiate
    idx::Int        # index of argument to differentiate against
    deriv::Deriv    # pattern of differentiation expression
end







