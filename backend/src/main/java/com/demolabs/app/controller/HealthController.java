package com.demolabs.app.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    // Plain endpoint kept separate from Actuator health so app-level readiness
    // logic can be extended later without touching the Actuator config.
    @GetMapping("/api/ping")
    public String ping() {
        return "pong from demolabs-backend";
    }
}
