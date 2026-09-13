package com.demolabs.app.controller;

import com.demolabs.app.model.Task;
import com.demolabs.app.repo.TaskRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/tasks")
@CrossOrigin(origins = "*")
public class TaskController {

    @Autowired
    private TaskRepository repo;

    @GetMapping
    public List<Task> all() {
        return repo.findAll();
    }

    @PostMapping
    public Task create(@RequestBody Task task) {
        return repo.save(task);
    }

    @GetMapping("/{id}")
    public Task one(@PathVariable Long id) {
        return repo.findById(id).orElseThrow();
    }
}
