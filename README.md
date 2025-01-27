# cgq

Canvas Group Quiz is a gleam CLI tool to create per-group quizzes.

## Usage
To create a quiz for a course, you will need the `course_id`.
You can list the courses where you are `TA` or `Teacher` via

```sh
gleam run -- list courses <enrollment_type>
```

This will show you a table of **active** course names and IDs:

```sh
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

```sh
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
> Future work will allow loading it through a file

```sh
gleam run -- create <course_id> \
    --title "Week 8" \
    --description "Weekly evaluations." \
    --quiz_type "graded_survey" \
    --assignment_group "<assignment_group_id>" \
    --due_at "2025-03-01 23:59.999-8:00" \
    --unlock_at "2025-02-01 23:59.999-8:00" \
    --published "False"
```

And it will print out the progress:
```sh
Creating quiz for group <group_name>...
Created quiz with ID <quiz_id>.  Adding quiz questions...
Questions created.  Assigning quiz to group...
Quiz assigned.
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
