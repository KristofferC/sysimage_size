using Dates, CSV, DataFrames, PlotlyJS

julia_repo() = joinpath(homedir(), "julia")

function process_data(input_file)
    df = CSV.read(input_file, DataFrame; header=false, delim=' ')
    rename!(df, [:commit, :size])
    commit_range = string(df[!,1][1], "..", df[!,1][end])

    # Get base dates for all commits
    function get_commit_date(commit)
        cmd = `git -C $(julia_repo()) show -s --format=%ci $commit`
        date_str = chomp(String(read(cmd)))
        DateTime(date_str[1:19], dateformat"yyyy-mm-dd HH:MM:SS")
    end

    df[!, :date] = [get_commit_date(c) for c in df.commit]

    # Create quick lookup structures
    commit_set = Set(df.commit)
    date_dict = Dict(row.commit => row.date for row in eachrow(df))

    # Process merge commits in the specified range
    merge_commits = readlines(`git -C $(julia_repo()) rev-list --merges $commit_range`)
    @show merge_commits
    for mc in merge_commits
        @show mc
          # Skip "Merge branch 'master' into" commits
        commit_msg = readchomp(`git log --format=%B -1 $mc`)
        if startswith(commit_msg, "Merge branch 'master' into")
            @info "Skipping merge commit $mc"
            continue
        end

        # Get merge commit date
        mc_date = get_commit_date(mc)

        # Get parent commits
        parents = split(readchomp(`git -C $(julia_repo()) log -1 --format=%P $mc`))
        length(parents) < 2 && continue  # Skip non-merge or octopus merges

        # Get merged branch commits
        merged_commits = readlines(`git -C $(julia_repo()) rev-list $(parents[2]) --not $(parents[1])`)

        # Update dates for merged commits present in our dataset
        @show mc => (merged_commits, mc_date)

        for c in merged_commits
            if c in commit_set
                date_dict[c] = mc_date
            end
        end
    end

    # Update dataframe with adjusted dates
    df[!, :date] = [date_dict[c] for c in df.commit]
    sort!(df, :date)

    return df
end

# Generate interactive plot
function create_plot(df)
    trace = scatter(
        x=df.date,
        y=df.size,
        mode="markers+lines",
        marker=attr(size=8, color="#2A9D8F"),
        line=attr(color="#264653"),
        text=["Commit: $(row.commit)<br>Date: $(row.date)" for row in eachrow(df)],
        customdata=df.commit,
        hoverinfo="text+y"
    )

    layout = Layout(
        title="Julia Sysimage Size History",
        xaxis_title="Commit Date",
        yaxis_title="Size (bytes)",
        plot_bgcolor="white",
        hovermode="closest",
        showlegend=false,
        annotations=[
            attr(
                x=0.5,
                y=-0.2,
                showarrow=false,
                text="Click points to view commit on GitHub",
                xref="paper",
                yref="paper"
            )
        ]
    )

    return Plot([trace], layout)
end

function save_interactive_plot(plt, filename)
    # Generate base plot HTML
    temp_file = tempname() * ".html"
    savefig(plt, filename)
end

# Main execution
df = process_data("sysimage_sizes.txt")
plt = create_plot(df)
save_interactive_plot(plt, "sysimage_history.html")
