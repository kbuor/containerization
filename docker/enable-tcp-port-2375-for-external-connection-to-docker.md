## Enable TCP port 2375 for external connection to Docker
---
See this issue.
Docker best practise to Control and configure Docker with systemd.

> Create daemon.json file in `/etc/docker`:
```shell
{
 "debug": true,
 "hosts": ["tcp://172.168.192.102:2376", "unix:///var/run/docker.sock"]
}
```

> Add `/etc/systemd/system/docker.service.d/override.conf`

```shell
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
```

> Reload the systemd daemon:

```shell
 systemctl daemon-reload
```

> Restart docker:

```shell
 systemctl restart docker.service
```

---
## Giải thích

1. Thư mục và tệp cấu hình

Thư mục `/etc/systemd/system/docker.service.d/` là nơi chứa các tệp cấu hình bổ sung để ghi đè (override) các thiết lập mặc định của dịch vụ Docker (`docker.service`). Tập tin `override.conf` là tập tin cấu hình tùy chỉnh được tạo ra để thay đổi một hoặc nhiều tham số của dịch vụ Docker.

2. Nội dung của tệp override.conf

```shell
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
```

> [Service]

[Service]: Đây là phần để chỉ định rằng bạn đang ghi đè các tham số trong phần dịch vụ của cấu hình Docker.

> ExecStart=

`ExecStart=`: Dòng này nhằm xóa bỏ (reset) thiết lập ExecStart mặc định. Trong các tệp cấu hình systemd, khi bạn chỉ định một giá trị rỗng cho ExecStart, bạn sẽ xóa lệnh khởi động mặc định của dịch vụ đó.

> ExecStart=/usr/bin/dockerd

`ExecStart=/usr/bin/dockerd`: Dòng này định nghĩa lại lệnh khởi động cho dịch vụ Docker. Ở đây, bạn thiết lập lại lệnh để khởi chạy Docker daemon (dockerd) từ đường dẫn /usr/bin/dockerd.


## Tại sao cần làm điều này?

1. Ghi đè cài đặt mặc định: Khi bạn muốn tùy chỉnh cách Docker daemon khởi động mà không sửa trực tiếp tệp dịch vụ gốc (`/lib/systemd/system/docker.service`), bạn tạo tệp ghi đè trong thư mục `/etc/systemd/system/docker.service.d/`.

2. Bảo mật và quản lý: Việc ghi đè cấu hình thông qua tập tin override.conf giúp dễ dàng quản lý và cập nhật mà không ảnh hưởng tới tệp dịch vụ gốc. Nếu Docker được cập nhật, các thiết lập tùy chỉnh của bạn sẽ không bị ghi đè.

3. Tùy chỉnh nâng cao: Bạn có thể thêm các tham số tùy chỉnh khác cho Docker daemon. Ví dụ: Bạn có thể thêm các tùy chọn dòng lệnh bổ sung cho dockerd để thay đổi cổng mặc định, địa chỉ API, hoặc các thiết lập mạng khác.
