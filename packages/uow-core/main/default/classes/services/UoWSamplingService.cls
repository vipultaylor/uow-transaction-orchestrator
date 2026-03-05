//------------------------------------------------------------------------------------------------//
// This file is part of the UoW Transaction Orchestrator project, released under the MIT License. //
// See LICENSE file or go to https://github.com/vipultaylor/uow-transaction-orchestrator           //
//------------------------------------------------------------------------------------------------//
/**
 * Service for sampling records with error-priority.
 * Failed records are always included first, then remaining capacity
 * is filled using the configured strategy (FIRST_N, LAST_N, RANDOM).
 * Used to reduce data size for auditing and snapshots.
 *
 * @author Vipul Taylor
 * @since 1.0.0
 * @group UoW Services
 */
public inherited sharing class UoWSamplingService {

    // ============================================================================
    // PUBLIC API
    // ============================================================================

    /**
     * Sample indices with error-priority.
     * Failed indices are always included first, then remaining capacity
     * is filled with successful indices using the configured strategy.
     *
     * @param totalCount Total number of records/events
     * @param failedIndices Set of indices that failed (may be null or empty)
     * @param config The serialization configuration (controls sampling behavior)
     * @return List of indices to include in snapshot (sorted by original order)
     */
    public static List<Integer> sampleIndices(
        Integer totalCount,
        Set<Integer> failedIndices,
        UoWSerializationConfig config
    ) {
        if (totalCount == null || totalCount <= 0) {
            return new List<Integer>();
        }

        // Normalize failedIndices
        Set<Integer> failures = failedIndices != null ? failedIndices : new Set<Integer>();

        // If sampling disabled, return all indices
        Boolean isEnabled = config?.applySampling ?? false;
        if (!isEnabled) {
            return getAllIndices(totalCount);
        }

        Integer maxRecords = config?.samplingCount ?? 5;

        // If total count fits within sample size, return all
        if (totalCount <= maxRecords) {
            return getAllIndices(totalCount);
        }

        UoWEnums.SamplingStrategy strategy = config?.samplingStrategy ?? UoWEnums.SamplingStrategy.FIRST_N;
        Set<Integer> selectedIndices = new Set<Integer>();

        // Step 1: Include ALL failed indices first (error-priority)
        if (!failures.isEmpty()) {
            if (failures.size() >= maxRecords) {
                // More failures than sample size - sample from failures using strategy
                selectedIndices.addAll(sampleFromIndices(failures, maxRecords, strategy));
            } else {
                // Include all failures
                selectedIndices.addAll(failures);
            }
        }

        // Step 2: Fill remaining capacity with successful indices
        Integer remainingCapacity = maxRecords - selectedIndices.size();
        if (remainingCapacity > 0) {
            // Build list of successful indices
            List<Integer> successIndices = new List<Integer>();
            for (Integer i = 0; i < totalCount; i++) {
                if (!failures.contains(i)) {
                    successIndices.add(i);
                }
            }

            // Sample from successful indices using strategy
            if (!successIndices.isEmpty()) {
                List<Integer> sampledSuccesses = sampleFromList(successIndices, remainingCapacity, strategy);
                selectedIndices.addAll(sampledSuccesses);
            }
        }

        // Step 3: Sort by original order for consistent output
        List<Integer> result = new List<Integer>(selectedIndices);
        result.sort();
        return result;
    }

    // ============================================================================
    // PRIVATE HELPER METHODS
    // ============================================================================

    // Generate list of all indices from 0 to count-1
    private static List<Integer> getAllIndices(Integer count) {
        List<Integer> indices = new List<Integer>();
        for (Integer i = 0; i < count; i++) {
            indices.add(i);
        }
        return indices;
    }

    // Sample from a Set of indices using strategy
    private static Set<Integer> sampleFromIndices(Set<Integer> indices, Integer count, UoWEnums.SamplingStrategy strategy) {
        List<Integer> indexList = new List<Integer>(indices);
        indexList.sort();
        List<Integer> sampled = sampleFromList(indexList, count, strategy);
        return new Set<Integer>(sampled);
    }

    // Sample from a List of indices using strategy
    private static List<Integer> sampleFromList(List<Integer> indices, Integer count, UoWEnums.SamplingStrategy strategy) {
        if (indices.size() <= count) {
            return indices;
        }

        List<Integer> sampled = new List<Integer>();

        switch on strategy {
            when FIRST_N {
                for (Integer i = 0; i < count; i++) {
                    sampled.add(indices[i]);
                }
            }
            when LAST_N {
                Integer start = indices.size() - count;
                for (Integer i = start; i < indices.size(); i++) {
                    sampled.add(indices[i]);
                }
            }
            when RANDOM {
                // Fisher-Yates shuffle for random sampling
                List<Integer> shuffled = new List<Integer>(indices);
                for (Integer i = 0; i < count; i++) {
                    Integer randomIndex = i + (Integer)(Math.random() * (shuffled.size() - i));
                    Integer temp = shuffled[i];
                    shuffled[i] = shuffled[randomIndex];
                    shuffled[randomIndex] = temp;
                    sampled.add(shuffled[i]);
                }
            }
        }

        return sampled;
    }
}