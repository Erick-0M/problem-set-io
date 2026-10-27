using MAT, JLD2, LinearAlgebra
include("blp_new.jl"); using .blp
d2 = matread("../build/input/public/simulation/100markets3products.mat")
ss = load("models_full/model_ss.jdl2")["model"]
X_supply = hcat(ones(ss.T*ss.J, 1), d2["Z"], d2["w"])
X_rivals = blp.compute_blp(ss)
Z_supply = hcat(ss.X, X_rivals, X_supply[:, 2:end])
for (name, Omega) in (("coll", ones(ss.J, ss.J)), ("comp", zeros(ss.J, ss.J)))
    dem = deepcopy(ss); dem.Omega = Omega
    sys = blp.BLP(BLPDemand = dem, BLPSupply = blp.BLPSupply(X = X_supply, Z = Z_supply, W = inv(Z_supply'*Z_supply)))
    println("Estimating $name ..."); flush(stdout)
    failures = []
    t = @elapsed blp.estimate_blp_joint!(sys; toler = 1e-10, max_iter = 10_000, Ns = 16, iterations = 100, time_limit = 600.0, failures = failures)
    jldsave("models_full/model_system_$name.jdl2"; model = sys)
    jldsave("models_full/model_system_$(name)_failed_starts.jdl2"; failures = failures)
    println("$name: $(length(failures)) of 16 starts failed")
    println("$name: $(round(t, digits = 1))s, params = ", round.(vec(sys.params), digits = 4))
end
