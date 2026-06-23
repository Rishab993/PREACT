"""
OR-Tools CP-SAT service for optimal officer-to-junction deployment.
"""
import logging
from typing import List, Dict, Any

logger = logging.getLogger(__name__)


def generate_deployment_plan(
    officers: List[Dict[str, Any]],
    junctions: List[Dict[str, Any]],
    event: Dict[str, Any],
) -> List[Dict[str, Any]]:
    """
    officers: [{id, badge_number, name, zone, shift_start, shift_end, available}]
    junctions: [{name, lat, lng, severity}]
    event: {id, start_dt, end_datetime, zone, expected_attendance}

    CP-SAT model:
    - Variables: assignment[o][j] in {0,1}
    - Constraints:
        * Each officer assigned to max 1 junction
        * Each junction receives at most 1 officer
        * Officer zone must match event zone OR officer available=True
        * High-severity junctions (> 0.7) get a 10x objective bonus
    - Objective: maximise sum(assignment[o][j] * weight[j]); always feasible
    - Solver timeout: 2s

    Returns: [{officer_id, officer_name, badge_number, junction, lat, lng,
               start_time, end_time, priority}]
    """
    try:
        from ortools.sat.python import cp_model

        if not officers or not junctions:
            logger.warning("generate_deployment_plan called with empty officers or junctions")
            return []

        event_zone = event.get("zone", "")
        start_time = event.get("start_dt", "")
        end_time = event.get("end_datetime", "")

        # Filter eligible officers: same zone or available flag
        eligible = [
            o for o in officers
            if o.get("zone") == event_zone or o.get("available", True)
        ]

        if not eligible:
            eligible = officers  # fallback: use all officers

        num_officers = len(eligible)
        num_junctions = len(junctions)

        model = cp_model.CpModel()

        # Decision variables: assignment[o][j]
        assignment = {}
        for o in range(num_officers):
            for j in range(num_junctions):
                assignment[(o, j)] = model.NewBoolVar(f"assign_o{o}_j{j}")

        # Constraint 1: Each officer assigned to at most 1 junction
        for o in range(num_officers):
            model.AddAtMostOne(assignment[(o, j)] for j in range(num_junctions))

        # Constraint 2: Each junction receives at most 1 officer
        for j in range(num_junctions):
            model.Add(sum(assignment[(o, j)] for o in range(num_officers)) <= 1)

        # Objective: maximise weighted severity coverage.
        # High-severity junctions (> 0.7) get a 10x bonus to strongly prioritize
        # them without making the model infeasible when officers < high-sev junctions.
        # Scale severity to integers (multiply by 1000); high-sev bonus x10.
        objective_terms = []
        for o in range(num_officers):
            for j in range(num_junctions):
                sev = junctions[j].get("severity", 0.0)
                weight = int(sev * 1000)
                if sev > 0.7:
                    weight *= 10
                objective_terms.append(assignment[(o, j)] * weight)
        model.Maximize(sum(objective_terms))

        solver = cp_model.CpSolver()
        solver.parameters.max_time_in_seconds = 2.0
        status = solver.Solve(model)

        logger.info(f"CP-SAT status = {solver.StatusName(status)}")

        results = []
        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            for o in range(num_officers):
                for j in range(num_junctions):
                    if solver.Value(assignment[(o, j)]) == 1:
                        officer = eligible[o]
                        junction = junctions[j]
                        sev = junction.get("severity", 0.0)
                        if sev >= 0.75:
                            priority = "high"
                        elif sev >= 0.45:
                            priority = "medium"
                        else:
                            priority = "low"

                        results.append({
                            "officer_id": officer.get("id", ""),
                            "officer_name": officer.get("name", ""),
                            "badge_number": officer.get("badge_number", ""),
                            "junction": junction.get("name", ""),
                            "lat": junction.get("lat", 0.0),
                            "lng": junction.get("lng", 0.0),
                            "start_time": start_time,
                            "end_time": end_time,
                            "priority": priority,
                        })
        else:
            logger.warning(f"CP-SAT solver status: {solver.StatusName(status)} — returning partial/empty plan")

        logger.info(f"Assignments returned = {len(results)}")
        return results

    except Exception as e:
        logger.error(f"OR-Tools deployment error: {e}")
        # Return partial solution on timeout or error
        fallback = []
        for i, officer in enumerate(officers[:len(junctions)]):
            if i < len(junctions):
                j = junctions[i]
                fallback.append({
                    "officer_id": officer.get("id", ""),
                    "officer_name": officer.get("name", ""),
                    "badge_number": officer.get("badge_number", ""),
                    "junction": j.get("name", ""),
                    "lat": j.get("lat", 0.0),
                    "lng": j.get("lng", 0.0),
                    "start_time": event.get("start_dt", ""),
                    "end_time": event.get("end_datetime", ""),
                    "priority": "medium",
                })
        return fallback