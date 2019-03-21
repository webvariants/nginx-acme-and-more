package main

import (
	"fmt"

	"flag"

	"github.com/fsouza/go-dockerclient"
)

func main() {
	var containerName string
	var signal int
	flag.StringVar(&containerName, "name", "", "container name")
	flag.IntVar(&signal, "signal", 1, "signal number default sighup")
	flag.Parse()
	endpoint := "unix:///var/run/docker.sock"
	client, err := docker.NewClient(endpoint)
	if err != nil {
		panic(err)
	}
	containers, err := client.ListContainers(docker.ListContainersOptions{All: false})
	if err != nil {
		panic(err)
	}
	for _, container := range containers {
		for _, name := range container.Names {
			if name == containerName {
				fmt.Println(container.ID, "signal", signal)
				client.KillContainer(docker.KillContainerOptions{ID: container.ID, Signal: docker.Signal(signal)})
			}
		}
	}
}
