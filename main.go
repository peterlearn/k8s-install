package main

import (
	"fmt"
	"net"
)

type MoneyType int32

type Test struct {
	Id   int
	Name string
}

func SafeDo(f func()) {
	go func() {
		defer func() {
			if err := recover(); err != nil {
				println("SafeDo err: ", err)
			}
		}()
		f()
		println("外层退出")
	}()
}

type FatherInfo struct {
	Id   int64
	Imei string
}

const (
	inviteByKey = "invite:by:%v"
)

func FormatInviteByKey(playerId int64) string {
	return fmt.Sprintf(inviteByKey, playerId)
}

const (
	REGION = "region"
	GAME   = "game"
	GROUP  = "group"
)

// 查看ip
func main() {
	ips, err := net.Interfaces()
	fmt.Errorf("err:%v", err)
	for _, v := range ips {
		fmt.Println(v.Addrs())
	}
}
