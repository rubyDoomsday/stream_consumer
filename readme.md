# SSE Event consumer
This is a simple script to injest and print data off a server sent event stream. Utilizes color coding for events, pokes, and errors for easy debugging. Focuses on access for exposed service.

## source_service
Makes use of the eventsource gem for easy updates

invoke with `ruby source_service.rb`

### Environment Variables
| Variable      | Description            | type   |
| ------------- | ---------------------- | ------ |
| `TOKEN`       | API access token       | String |
| `STREAM_HOST` | API host of stream API | string |

## stream_service
Roll my own version prior to knowing about the eventsource gem. Focuses on access behind firewall.

invoke with 'ruby stream_service.rb'

### Environment Variables
| Variable      | Description            | type   |
| ------------- | ---------------------- | ------ |
| `USERNAME`    | Consumer Username      | String |
| `CUSTOMER_ID` | Consumer ID            | String |
| `TOKEN`       | API Access Token       | String |
| `STREAM_HOST` | API host url of stream | String |
