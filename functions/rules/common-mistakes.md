# Common Calculus 1 Mistakes

Watch for these errors in student work. When you spot one, gently flag it, explain why it's wrong, and show the correct approach.

## Derivatives

- **Forgetting the Chain Rule**: Differentiating sin(x²) as cos(x²) instead of cos(x²) · 2x. Always ask: "Is there a function inside another function?"
- **Product Rule errors**: Writing d/dx[f·g] = f'·g' instead of f'·g + f·g'. The derivative of a product is NOT the product of the derivatives.
- **Quotient Rule sign error**: Mixing up the order in (g·f' - f·g')/g² vs. the correct (f'·g - f·g')/g². Remember: "low d-high minus high d-low, over the square of what's below."
- **Power Rule on constants**: Writing d/dx[5] = 5·x⁰ = 5 instead of 0. The derivative of a constant is always 0.
- **Confusing d/dx[eˣ] with d/dx[xⁿ]**: The exponential function eˣ is its own derivative. It does NOT use the Power Rule.

## Limits

- **Misapplying L'Hôpital's Rule**: Using L'Hôpital when the form is NOT 0/0 or ∞/∞. Always verify the indeterminate form before applying the rule.
- **Incorrect limit notation**: Writing lim f(x) = 0/0. The limit is never "equal to" an indeterminate form — 0/0 describes the *form*, not the *value*.
- **Ignoring one-sided limits**: Concluding a limit exists when left and right limits disagree. The two-sided limit exists only if both one-sided limits are equal.

## Integrals

- **Dropping +C**: Forgetting the constant of integration on indefinite integrals. Every antiderivative has a family of solutions.
- **u-substitution bounds error**: Forgetting to change the limits of integration when substituting in a definite integral, or mixing old and new variables.
- **Antiderivative of 1/x**: Writing ln(x) instead of ln|x|. The absolute value matters for negative inputs.
- **Reversing the Fundamental Theorem**: Confusing ∫f'(x)dx = f(x)+C with d/dx[∫f(t)dt] = f(x). Know which direction you're going.

## Applications

- **Optimization: forgetting to check endpoints**: Finding a critical point but not verifying it's actually a maximum or minimum, or ignoring the endpoints on a closed interval.
- **Related rates: substituting too early**: Plugging in specific values BEFORE differentiating. You must differentiate first, then substitute known values.
- **Confusing f, f', and f''**:
  - f(x) = position, value of the function
  - f'(x) = slope, rate of change, velocity (increasing/decreasing)
  - f''(x) = concavity, acceleration (concave up/down)
- **Assuming continuity implies differentiability**: A function can be continuous at a point but not differentiable there (e.g., |x| at x = 0).

## General

- **Algebraic errors under pressure**: Sign mistakes, distribution errors, and incorrect factoring are the most common source of wrong answers. Encourage students to slow down and check each algebraic step.
- **Misreading interval notation**: Confusing open (a, b) with closed [a, b] intervals. This matters for the Extreme Value Theorem and continuity conditions.
- **Not stating hypotheses**: Applying a theorem without verifying its conditions are met (e.g., using the Mean Value Theorem without checking continuity on [a,b] and differentiability on (a,b)).
