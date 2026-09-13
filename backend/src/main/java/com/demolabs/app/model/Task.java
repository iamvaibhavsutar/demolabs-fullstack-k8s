package com.demolabs.app.model;

import jakarta.persistence.*;

@Entity
@Table(name = "tasks")
public class Task {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String title;
    private boolean done;

    public Task() {}
    public Task(String title, boolean done) { this.title = title; this.done = done; }

    public Long getId() { return id; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public boolean isDone() { return done; }
    public void setDone(boolean done) { this.done = done; }
}
