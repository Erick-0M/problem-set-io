using MAT, Statistics, LinearAlgebra
const SRC = ARGS[1]
include(SRC); using .blp
simdir = "/Users/erickom/Documents/GitHub/problem-set-io/code/build/input/public/simulation"
d = matread(joinpath(simdir, ARGS[2]))
gamma = [2,1,1]
J, T = size(d["P_opt"])
p = reshape(d["P_opt"], (T*J,1)); shares = reshape(d["shares"], (T*J,1))
data = blp.BLPData(T, J, d["x1"], p, shares, log.(d["alphas"] .- 1))
model = blp.BLPDemand(BLPData=data)
model.xi_real = d["xi_all"]
model.cost = gamma[1] .+ (gamma[2]*d["w"] + gamma[3]*d["Z"] + d["eta"])
model.beta .= vcat([5,1,1],[-1]); model.sigma = 1.0
delta = model.X_all*model.beta + model.xi_real
blp.simulate_BLP!(model, delta=delta, sigma=1.0, all=true)
pb = blp.compute_hausman(model); Xr = blp.compute_blp(model)
model.Z = hcat(model.X, pb, Xr); model.W = inv(model.Z'*model.Z)
blp.estimate_blp!(model; Ns=3, toler=1e-12, iterations=50)  # warm
t = @elapsed blp.estimate_blp!(model; Ns=3, toler=1e-12, iterations=50)
println("DEMAND time=$t params=", model.params, " se=", sqrt.(diag(model.Var)))
dem = deepcopy(model)
dem.Z = hcat(dem.X, pb, Xr, d["w"]); dem.W = inv(dem.Z'*dem.Z)
Xs = hcat(ones(T*J,1), d["Z"], d["w"]); Zs = hcat(dem.X, Xr, Xs[:,2:end])
for (nm, Om) in (("bert", I(J)), ("coll", ones(J,J)), ("comp", zeros(J,J)))
    dd = deepcopy(dem); dd.Omega = Matrix{Float64}(Om)
    sys = blp.BLP(BLPDemand=dd, BLPSupply=blp.BLPSupply(X=Xs, Z=Zs, W=inv(Zs'*Zs)))
    t = @elapsed blp.estimate_blp_joint!(sys; Ns=2, toler=1e-12, iterations=30)
    println("JOINT $nm time=$t params=", vec(sys.params), " se=", sqrt.(abs.(diag(sys.Var))))
end
