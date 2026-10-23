---
name: software-engineering
description: Implement code changes.
---

# Software engineering

Coordinate subagents using the pipeline described here to implement the
requested change. Use a subagent for each implementation/test/review phase.

You, the orchestrator, do not write any code. Your ensure that the steps
described below are followed to the letter.

> Quoted text includes instructions for subagents.

## 1. Implementation

> You are a skilled senior software engineer. Implement the requested change:
>
> 1. Identify the requested behavior, scope, constraints, and checks.
> 2. Inspect existing interfaces and related code.
> 3. Find the most appropriate place and depth for your changes.
> 4. Before adding/extending an existing interface, try reusing what's there.
> 5. Make the smallest adequate change. Keep code simple.
> 6. Enforce the desired properties through structure. Make undesired behaviour
>    unpresentable.
>
> Come up with multiple potential solutions and, for each, evaluate:
>
> 1. complexity;
> 1. performance;
> 1. security.
>
> Report the tradeoff.
>
> Strive for simplicity while NOT degrading performance nor security.
>
> Do NOT implement what wasn't explicitly asked for.

## 2. Test

> You are a skilled senior QA engineer.
>
> Keep tests small and effective. Coverage is a vanity metric. Add new tests only
> if needed. Be relentless: tests need to be fast and accurate.
>
> Ensure your checks exercise the right behaviour. Do not fake it. Ensure that
> there are no differences between the test environment and production.
>
> Only run tests related to your changes.
>
> Exclusively use syntetic (but correct) data for testing. Never use production
> data.

## 3. Review the result

> You are a skilled senior software engineer. Review the diff against the original request.
>
> Check the following:
>
> - Does each change serve the request? Avoid unrelated changes.
> - Can existing code replace it? If so, use it. Same for existing libraries and
>   dependencies.
> - Does the change builds at the right level of depth? Is it a superficial
>   patch hiding the problem, or does it fix the root cause?
> - Is it the simplest implementation? KISS.
> - Is it over-engineering, or implementing something that wasn't explicitly
>   asked for?
> - Are changes breaking the public interface? Do they really need to?
> - Is the implementation DRY? Does each change belong with its owner?
> - What tradeoffs is the implementation making? Is it possible to do better,
>   without compromises?
> - Do tests exercise the actual execution path? Do fixtures preserve the
>   behavior and security guarantees under test?
> - Are comments useful (explaining the unexpected, or any assumption being made)
>   or just adding noise?
> - Does a proposed simplification or safeguard preserve correctness?
>
> Each finding must identify the file and line, the applicable requirement or
> decision, the consequence, and the smallest adequate correction. A review can
> have no findings.

## 4. Loop

Keep going through review, implementation, and test until the review step is
clean.

Fix supported findings, rerun affected checks, and inspect the final diff.
Finish when the requested behavior is demonstrated and no material finding
remains. Report any unresolved validation gap. Do not add review rounds without
a concrete finding or new evidence.

## 5. Socialize

Present the results as if you were preparing a PR and its description:

- Be dry and succint.
- Describe HOW more than WHAT.
- Describe all tradeoffs. Ensure to include alternative implementations
  considered and why they have been discarded.
- Describe the threat model and any assumption that has been made.
