# cgq

Canvas Group Quiz is a gleam CLI tool to create per-group quizzes.

## Usage
> [!IMPORTANT]
> You need to set the env var `CANVAS_API_TOKEN` to your API token.
> You can find the steps to get it [here](https://learninganalytics.ubc.ca/guides/get-started-with-the-canvas-api/).

If you want to change the domain for the canvas API, you can set the `CANVAS_API_DOMAIN` env var.

To create a quiz for a course, you will need the `course_id`.
You can list the courses where you are `TA` or `Teacher` via

```sh
gleam run -- list courses <enrollment_type>
```

This will show you a table of **active** course names and IDs:

```
┌───────────────────────────────────────────────────────────────────────────────────┬────────┐
│                                       Name                                        │   ID   │
├───────────────────────────────────────────────────────────────────────────────────┼────────┤
│ COSC_O 310 101 2024W2 Software Engineering                                        │ ###### │
│ COSC_O 419O O_101 COSC_O 536K_101 2024W2 Topics in Computer Science - MINING DATA │ ###### │
└───────────────────────────────────────────────────────────────────────────────────┴────────┘
```

If you want to assign the created quiz to a specific `assignment_group`, you can use the list assignment group command.
The command is 

```sh
gleam run -- list assignment_groups <course_id>
```

It will show you the following table:

```
┌─────────────┬────────┐
│    Name     │   ID   │
├─────────────┼────────┤
│ Other       │ ###### │
│ Assignments │ ###### │
│ Project     │ ###### │
│ Quizzes     │ ###### │
└─────────────┴────────┘
```

You can create a quiz using the following command:

> [!IMPORTANT]
> Currently, questions can only be created in gleam code itself.
> Future work will allow loading it through a file.
> You can see the code in [cgq.gleam](./src/cgq.gleam).

```sh
gleam run -- create <course_id> \
    --title "Week 5" \
    --description "Weekly evaluations." \
    --quiz_type "graded_survey" \
    --assignment_group_id "<assignment_group_id>" \
    --due_at "2025-02-14 23:59.999-8:00" \
    --unlock_at "2025-02-07 23:59.999-8:00" \
    --published "False"
```

> [!NOTE]
> The group name will be added to the quiz title.

And it will print out the progress:
```
Creating quiz for group <group_name>...
Created quiz with ID <quiz_id>.  Adding quiz questions...
Questions created.  Assigning quiz to group...
Quiz assigned.
```

You can also make a quiz for a single group using the `<group_id>` option:

```sh
gleam run -- create <course_id> \
    --group_id "<group_name>" \
    --title "Week 5" \
    --description "Weekly evaluations." \
    --quiz_type "graded_survey" \
    --assignment_group_id "<assignment_group_id>" \
    --due_at "2025-02-14 23:59.999-8:00" \
    --unlock_at "2025-02-07 23:59.999-8:00" \
    --published "False"
```

To get an ID for a group, you can use the command

```sh
gleam run -- list groups <course_id>
```

Which will output something like:
```
┌────────────────────────┬────────┬─────────┐
│          Name          │   ID   │ Members │
├────────────────────────┼────────┼─────────┤
│ A                      │ ###### │       6 │
│ BrethooCodes           │ ###### │       5 │
│ Teams 15               │ ###### │       5 │
│ Teams 21               │ ###### │       5 │
│ The Stragglers         │ ###### │       5 │
└────────────────────────┴────────┴─────────┘
```

## Development

To build locally you can use
```sh
gleam clean
gleam run
```

To build the release version, you will need to
```sh
mix deps.get
mix clean
mix compile
mix release
```

This will use [burrito](https://github.com/burrito-elixir/burrito) to build the application into `burrito_out`.

If you want to rebuild the application, you have to clear the cache:
```sh
burrito_out/<binary_name> maintenance uninstall
```

In the future, I plan to use `nix` for building the executables with a workflow for publishing.
