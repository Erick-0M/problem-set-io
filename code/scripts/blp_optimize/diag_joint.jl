using JLD2, LinearAlgebra
include("blp_new.jl"); using .blp
for n in ("bert","comp")
    sys = load("models_quick/model_system_$n.jdl2")["model"]
    d, s = sys.BLPDemand, sys.BLPSupply
    println(n, ": Omega=", d.Omega, " sigma=", d.sigma)
    for sg in (0.7, 0.92, 1.1)
        delta = blp.contraction(d, sg, toler=1e-8)
        B = (d.X_all'*d.Z*d.W*d.Z'*d.X_all) \ (d.X_all'*d.Z*d.W*d.Z')
        d.beta = B*delta
        _, cost = blp.simulate_BLP!(d, delta=delta, sigma=sg, supply=true)
        gs = s.Z' * (s.M * cost); gd = d.Z' * (d.M*delta)
        println("  sigma=$sg  demand obj=", dot(gd, d.W*gd), "  supply obj=", dot(gs, s.W*gs), "  cost range=", extrema(cost))
    end
end
